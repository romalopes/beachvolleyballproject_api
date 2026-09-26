# Computes an assessment session's ranking from the result rows already stored
# against it. Ranking is server-owned: clients receive the result, never submit
# it.
#
# Only complete rows are ranked. An included player with a missing category is
# reported in `incomplete` with the exact missing category ids — never as zero —
# and excluded players are reported separately so a deliberate absentee is not
# confused with an unscored player.
class AssessmentSessionRanking
  def initialize(session)
    @session = session
  end

  def call
    complete = []
    incomplete = []

    included_participants.each do |participant|
      assessment = assessment_for(participant.player_profile_id)
      missing = missing_category_ids(assessment)
      entry = entry_for(participant, assessment, missing)

      if complete_result?(assessment, missing)
        complete << entry.merge(status: "complete", overall_score: assessment.score)
      else
        incomplete << entry.merge(status: result_status(assessment, missing), overall_score: nil)
      end
    end

    assign_ranks!(complete.sort_by { |row| [ -row[:overall_score], row[:player_profile_id] ] })

    {
      ranking: complete,
      incomplete: incomplete,
      excluded: excluded_participants
    }
  end

  private

  attr_reader :session

  def included_participants
    session.participants.includes(player_profile: :person).included.to_a
  end

  def excluded_participants
    session.participants.includes(player_profile: :person).excluded.map do |participant|
      {
        player_profile_id: participant.player_profile_id,
        player_name: player_name(participant),
        status: "excluded",
        overall_score: nil,
        rank: nil,
        missing_category_ids: [],
        missing_reason: participant.missing_reason
      }
    end
  end

  def assessments_by_player
    @assessments_by_player ||=
      session.assessments
             .includes(assessment_category_scores: :assessment_category)
             .where(player_profile_id: included_participants.map(&:player_profile_id))
             .group_by(&:player_profile_id)
  end

  def assessment_for(player_profile_id)
    assessments_by_player[player_profile_id]&.max_by(&:id)
  end

  def expected_category_ids
    @expected_category_ids ||=
      session.assessment_definition.assessment_categories.order(:position, :id).pluck(:id)
  end

  def missing_category_ids(assessment)
    return expected_category_ids if assessment.nil?

    rated = assessment.assessment_category_scores
                      .select { |row| row.criterion_id.nil? && row.rated? }
                      .map(&:assessment_category_id)
    expected_category_ids - rated
  end

  def complete_result?(assessment, missing)
    assessment.present? &&
      !assessment.withdrawn? &&
      missing.empty? &&
      assessment.score.present?
  end

  def result_status(assessment, missing)
    return "incomplete" if assessment.nil?
    return "withdrawn" if assessment.withdrawn?
    return "incomplete" if missing.any? || assessment.score.nil?

    "complete"
  end

  def entry_for(participant, assessment, missing)
    {
      player_profile_id: participant.player_profile_id,
      player_name: player_name(participant),
      assessment_id: assessment&.id,
      overall_score: nil,
      rank: nil,
      missing_category_ids: missing
    }
  end

  def player_name(participant)
    participant.player_profile.full_name.presence || "Player ##{participant.player_profile_id}"
  end

  # Standard competition ranking (D15): equal scores share a rank and the next
  # rank skips the tied count (`1, 2, 2, 4`). The presentation order is made
  # deterministic by player id without changing the rank itself.
  def assign_ranks!(rows)
    previous_score = nil
    previous_rank = nil

    rows.each_with_index do |row, index|
      row[:rank] = if row[:overall_score] == previous_score
                     previous_rank
      else
                     index + 1
      end
      previous_score = row[:overall_score]
      previous_rank = row[:rank]
    end

    rows
  end
end
