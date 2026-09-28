# Phase 4 (Ranking Consolidation): one frozen ranking snapshot per
# consolidation/source-session pair.
#
# `ranking_snapshot` is an array of `{ player_profile_id, overall_score, rank }`
# captured at creation time. The consolidation reads snapshots, never the live
# session, so later edits or withdrawals cannot rewrite history (D24).
#
# `excluded_from_snapshot` is this row's own record of the merge: true when the
# builder deliberately snapshotted this source as empty because it was withdrawn at
# the time. It is the authoritative answer to "are these scores in the ranking?",
# and it survives the source changing state afterwards — which is what makes a
# restored session detectable.
class RankingConsolidationSession < ApplicationRecord
  belongs_to :ranking_consolidation, inverse_of: :consolidation_sessions
  belongs_to :assessment_session

  validates :assessment_session_id,
            uniqueness: { scope: :ranking_consolidation_id }

  # Whether this source's scores are in the stored figures.
  def included_in_ranking?
    !excluded_from_snapshot?
  end

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
