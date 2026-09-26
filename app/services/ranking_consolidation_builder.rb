# Builds an immutable ranking consolidation from several coaches' published
# assessment sessions (plan §8, D20–D22).
#
# Compatibility is validated before anything is written, and the whole build
# runs in one transaction: every source session must be published and share
# the consolidation's definition. Each session's complete ranking is frozen
# into a snapshot; per-player rows then merge the snapshots by averaging over
# covered sessions only. A player missing from any source session is listed in
# `missing_players`, never assigned zero (D21).
#
# Raises `Error` (carrying `errors`) when the sessions are incompatible; the
# caller renders 422. Returns the persisted `RankingConsolidation`.
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

    snapshots = sessions.to_h do |session|
      [ session.id, AssessmentSessionRanking.new(session).call[:ranking] ]
    end
    validate_coverage!(sessions, snapshots)

    consolidation = nil
    RankingConsolidation.transaction do
      consolidation = RankingConsolidation.create!(
        assessment_definition: assessment_definition,
        name: name,
        notes: notes,
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

  # Every source session must have complete coverage for a merge to be honest:
  # a session that left players incomplete cannot contribute a trustworthy
  # average, so the consolidation is refused instead of silently dropping them.
  def validate_coverage!(sessions, snapshots)
    failures = []
    sessions.each do |session|
      ranking = AssessmentSessionRanking.new(session).call
      incomplete_names = ranking[:incomplete].map { |row| row[:player_name] }
      if incomplete_names.any?
        failures << "Session \"#{session.name}\" has incomplete players: #{incomplete_names.join(", ")}"
      end
      snapshots[session.id] = ranking[:ranking]
    end
    raise Error, failures if failures.any?
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
  # `coverage < sessions.size` on their row — no zero-filling, no exclusion.
end
