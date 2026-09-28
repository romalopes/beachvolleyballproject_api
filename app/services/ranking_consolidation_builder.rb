# Builds a club-level ranking consolidation from several coaches' assessment
# sessions (plan §8, D20–D22).
#
# Compatibility is validated before anything is written, and the whole build
# runs in one transaction: every source session must share the consolidation's
# definition. Each session's complete ranking is frozen into a snapshot;
# per-player rows then merge the snapshots by averaging over the sessions that
# actually scored the player.
#
# Source sessions do **not** have to be published here. A club ranking is
# assembled from several coaches' work that is often still in progress, so the
# result is created as a *draft* and publication is a separate, later step that
# requires every source to be published and re-derives the snapshot first.
# Gating publication at creation is what made the workflow impossible before.
#
# D21 (ratified) is a *never-block* policy: a missing or incomplete player never
# stops a consolidation and is never assigned zero. Incomplete players are
# absent from their session's snapshot, so their row's `coverage` falls below
# `session_count`, and each affected session is recorded on the consolidation as
# `source_warnings` so the reason survives even if the source changes later.
#
# Raises `Error` (carrying `errors`) only for genuinely invalid input — an empty
# selection, an unknown session id, or a mismatched definition — so the caller
# can render 422. Returns the persisted `RankingConsolidation`.
class RankingConsolidationBuilder
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  # `session_ids` is optional: `refresh!` re-derives from a consolidation's own
  # sources, so a caller that only refreshes must not have to restate them. The
  # empty default is safe because `validate_sessions!` refuses an empty set — a
  # caller that passes nothing by accident gets the "at least one session" error
  # rather than a silently empty consolidation.
  def initialize(assessment_definition:, session_ids: nil, name: nil, notes: nil, current_user: nil)
    @assessment_definition = assessment_definition
    @session_ids = Array(session_ids).map(&:to_i).uniq
    @name = name
    @notes = notes
    @current_user = current_user
  end

  def call
    sessions = load_sessions
    validate_sessions!(sessions)

    snapshots, warnings = snapshot_sessions(sessions)

    consolidation = nil
    RankingConsolidation.transaction do
      consolidation = RankingConsolidation.create!(
        assessment_definition: assessment_definition,
        name: name,
        notes: notes,
        source_warnings: warnings,
        created_by: current_user
      )
      write_snapshots(consolidation, sessions, snapshots)
      build_rows!(consolidation, snapshots)
    end
    consolidation
  end

  # Re-derive an existing draft's snapshot and rows from its current source
  # sessions. This is what makes the draft phase safe: a source session that was
  # still being scored when the consolidation was built has since changed, and
  # publishing that stale snapshot would be a club ranking disagreeing with the
  # sessions behind it.
  #
  # Refuses on a published consolidation — immutability begins at publish (D24) —
  # unless `force` is given, which only a supervised recalculation does. A
  # *withdrawn* ranking is refused either way: a retraction is ended by `restore`,
  # not rewritten in place.
  def refresh!(consolidation, force: false)
    if consolidation.published? && !force
      raise Error, "A published ranking cannot be rebuilt"
    end

    if consolidation.withdrawn?
      raise Error, "A withdrawn ranking can only be restored, not recalculated"
    end

    sessions = consolidation.assessment_sessions
                      .includes(:assessment_definition, :coach_profile)
                      .to_a
    raise Error, "At least one assessment session is required" if sessions.empty?

    validate_sessions!(sessions)
    snapshots, warnings = snapshot_sessions(sessions)

    RankingConsolidation.transaction do
      # Deleted through the class, not the loaded association. `destroy_all` on a
      # loaded collection also leaves its records in the in-memory target, and
      # `build_rows!` then appends to that target — so a re-derivation would keep the
      # previous rows alongside the new ones. A scope delete leaves nothing loaded, so
      # the merge below starts from empty either way.
      RankingConsolidationSession.where(ranking_consolidation_id: consolidation.id)
                                 .delete_all
      RankingConsolidationRow.where(ranking_consolidation_id: consolidation.id)
                             .delete_all
      write_snapshots(consolidation, sessions, snapshots)
      build_rows!(consolidation, snapshots)
      consolidation.source_warnings = warnings
      consolidation.save!
    end

    # The scope deletes above bypass the loaded associations, so a caller reading
    # `consolidation.rows` straight after a refresh would still be handed the rows
    # that were just deleted. Resetting the caches makes the returned object agree
    # with what was actually written, instead of forcing every caller to remember to
    # reload.
    consolidation.reload
    consolidation
  end

  private

  attr_reader :assessment_definition, :session_ids, :name, :notes, :current_user

  def load_sessions
    sessions = AssessmentSession.where(id: session_ids)
                                .includes(:assessment_definition, :coach_profile)
                                .to_a
    found = sessions.map(&:id)
    missing = session_ids - found
    raise Error, missing.map { |id| "Assessment session #{id} was not found" } if missing.any?

    # Stable order so snapshots, rows, and error messages are deterministic.
    sessions.sort_by(&:id)
  end

  # D20: one shared definition, and a non-empty selection.
  #
  # Publication is deliberately *not* required here. A consolidation is assembled
  # from sessions that may still be being scored, and gating that at creation is
  # what made this workflow impossible. Publication is gated at publish time by
  # `RankingConsolidation#publishable?` instead, and the snapshot is re-derived
  # there so nothing stale is ever frozen.
  def validate_sessions!(sessions)
    raise Error, "At least one assessment session is required" if sessions.empty?

    failures = sessions.filter_map do |session|
      next if session.assessment_definition_id == assessment_definition.id

      "Session \"#{session.name}\" uses a different assessment definition"
    end
    raise Error, failures if failures.any?
  end

  # D21 (ratified): never block. Snapshot whatever complete rows each session has
  # and record the sessions that left players incomplete, instead of refusing the
  # build. An incomplete player is absent from their session's ranking — never
  # zeroed — so their merged row simply reports lower coverage.
  #
  # A withdrawn source is snapshotted as *empty*, not refused. Its scores are
  # dropped from the merge, but the session keeps its join row and gets a warning:
  # the coach still sees which session was excluded and why, rather than the ranking
  # quietly resting on fewer sessions than were chosen. That is what lets a withdrawn
  # session be neither a silent omission nor a permanent blocker on publishing.
  #
  # Returns [snapshots, warnings]; warnings are persisted as `source_warnings`.
  def snapshot_sessions(sessions)
    snapshots = {}
    warnings = []

    sessions.each do |session|
      if session.withdrawn?
        snapshots[session.id] = []
        warnings << {
          assessment_session_id: session.id,
          name: session.name,
          incomplete_count: 0,
          incomplete_players: [],
          reason: "source_session_withdrawn"
        }
        next
      end

      ranking = AssessmentSessionRanking.new(session).call
      snapshots[session.id] = ranking[:ranking]

      incomplete_names = ranking[:incomplete].map { |row| row[:player_name] }
      next if incomplete_names.empty?

      warnings << {
        assessment_session_id: session.id,
        name: session.name,
        incomplete_count: incomplete_names.size,
        incomplete_players: incomplete_names
      }
    end

    [ snapshots, warnings ]
  end

  # `excluded` is the builder's own record of what it did, recorded in the same pass
  # that produces the empty snapshot. Deriving it later from timestamps is what let a
  # restored session look included while contributing nothing.
  def write_snapshots(consolidation, sessions, snapshots)
    sessions.each do |session|
      consolidation.consolidation_sessions.create!(
        assessment_session: session,
        excluded_from_snapshot: snapshots[session.id].empty? && session.withdrawn?,
        ranking_snapshot: snapshots[session.id].map do |row|
          row.slice(:player_profile_id, :overall_score, :rank)
        end
      )
    end
  end

  # Average over covered sessions only; standard competition ranking
  # (`1, 2, 2, 4`) over the averages with player id as the deterministic
  # presentation order — the same rule single sessions use (D15).
  def build_rows!(consolidation, snapshots)
    per_player = Hash.new { |hash, key| hash[key] = {} }
    snapshots.each do |session_id, rows|
      rows.each do |row|
        per_player[row[:player_profile_id]][session_id] = row[:overall_score]
      end
    end

    built = per_player.map do |player_profile_id, scores|
      average = (scores.values.sum.to_f / scores.size).round
      {
        player_profile_id: player_profile_id,
        coach_scores: scores,
        coverage: scores.size,
        average_score: average
      }
    end

    # Standard competition ranking over the averages (same rule as single
    # sessions, D15): equal averages share a rank, the next rank skips ahead.
    previous_score = nil
    previous_rank = nil
    built.sort_by { |row| [ -row[:average_score], row[:player_profile_id] ] }
         .each_with_index do |row, index|
      row[:rank] = if row[:average_score] == previous_score
                     previous_rank
      else
                     index + 1
      end
      previous_score = row[:average_score]
      previous_rank = row[:rank]
      consolidation.rows.create!(row)
    end
  end

  # Players ranked by some sessions but not all: reported explicitly (D21) via
  # `coverage < session_count` on their row, with the contributing sessions
  # listed in `source_warnings` — no zero-filling, no exclusion, no refusal.
end
