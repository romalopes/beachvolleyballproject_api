# Phase 4 (Ranking Consolidation): one frozen row per ranked player (D22).
#
# `coach_scores` maps `assessment_session_id -> overall_score`; `coverage` is
# the number of source sessions that ranked the player; `average_score` is the
# rounded mean over covered sessions only; `rank` is standard competition
# ranking over the averages. All four are computed once at creation and then
# never change.
class RankingConsolidationRow < ApplicationRecord
  belongs_to :ranking_consolidation, inverse_of: :rows
  belongs_to :player_profile

  validates :player_profile_id,
            uniqueness: { scope: :ranking_consolidation_id }

  # Session ids as integers — JSON object keys deserialize as strings.
  def scores_by_session
    (coach_scores || {}).each_with_object({}) do |(session_id, score), memo|
      memo[session_id.to_s.to_i] = score
    end
  end
end
