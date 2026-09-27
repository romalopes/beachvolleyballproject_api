# Builds an immutable ranking consolidation from several coaches' published
# assessment sessions (plan §8, D20–D22).
#
# Compatibility is validated before anything is written, and the whole build
# runs in one transaction: every source session must be published and share
# the consolidation's definition. Each session's complete ranking is frozen
# into a snapshot; per-player rows then merge the snapshots by averaging over
# the sessions that actually scored the player.
#
# D21 (ratified) is a *never-block* policy: a missing or incomplete player never
# stops a consolidation and is never assigned zero. Incomplete players are
# absent from their session's snapshot, so their row's `coverage` falls below
# `session_count`, and each affected session is recorded on the consolidation as
# `source_warnings` so the reason survives even if the source changes later.
#
# Raises `Error` (carrying `errors`) only for genuinely invalid input — an empty
# selection, an unknown session id, a draft session, or a mismatched definition
# — so the caller can render 422. Returns the persisted `RankingConsolidation`.
class RankingConsolidationBuilder
  class Error < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join(", "))
    end
  end

  def initialize(assessment_definition:, session_ids:, name: nil, notes: nil, current_user: nil)
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
      sessions.each do |session|
        consolidation.consolidation_sessions.create!(
          assessment_session: session,
          ranking_snapshot: snapshots[session.id].map do |row|
            row.slice(:player_profile_id, :overall_score, :rank)
          end
        )
      end
      build_rows!(consolidation, sessions, snapshots)
    end
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

  # D20: published only, one shared definition.
  def validate_sessions!(sessions)
    raise Error, "At least one assessment session is required" if sessions.empty?

    failures = []
    sessions.each do |session|
      unless session.published?
        failures << "Session \"#{session.name}\" is #{session.status}, not published"
        next
      end
      if session.assessment_definition_id != assessment_definition.id
        failures << "Session \"#{session.name}\" uses a different assessment definition"
      end
    end
    raise Error, failures if failures.any?
  end

  # D21 (ratified): never block. Snapshot whatever complete rows each session has
  # and record the sessions that left players incomplete, instead of refusing the
  # build. An incomplete player is absent from their session's ranking — never
  # zeroed — so their merged row simply reports lower coverage.
  #
  # Returns [snapshots, warnings]; warnings are persisted as `source_warnings`.
  def snapshot_sessions(sessions)
    snapshots = {}
    warnings = []

    sessions.each do |session|
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

  # Average over covered sessions only; standard competition ranking
  # (`1, 2, 2, 4`) over the averages with player id as the deterministic
  # presentation order — the same rule single sessions use (D15).
  def build_rows!(consolidation, sessions, snapshots)
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
