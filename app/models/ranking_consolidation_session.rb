# Phase 4 (Ranking Consolidation): one frozen ranking snapshot per
# consolidation/source-session pair.
#
# `ranking_snapshot` is an array of `{ player_profile_id, overall_score, rank }`
# captured at creation time. The consolidation reads snapshots, never the live
# session, so later edits or withdrawals cannot rewrite history (D24).
class RankingConsolidationSession < ApplicationRecord
  belongs_to :ranking_consolidation, inverse_of: :consolidation_sessions
  belongs_to :assessment_session

  validates :assessment_session_id,
            uniqueness: { scope: :ranking_consolidation_id }

  # Scores keyed by player id for the merge step: string keys are normalized
  # to integers because JSON object keys always deserialize as strings.
  def scores_by_player
    Array(ranking_snapshot).each_with_object({}) do |entry, memo|
      id = entry["player_profile_id"] || entry[:player_profile_id]
      score = entry["overall_score"] || entry[:overall_score]
      memo[id.to_i] = score
    end
  end
end
