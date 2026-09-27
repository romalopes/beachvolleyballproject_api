# Phase 4 (Ranking Consolidation), plan §8: an immutable snapshot merging
# several coaches' published session results into one club-level ranking.
#
# Once created a consolidation never changes (D24): source sessions are
# snapshotted, not referenced live, so withdrawing a source later leaves this
# record exactly as it was.
#
# `source_warnings` is why this record stays honest without re-reading the
# sources: under D21 a merge never blocks over missing or incomplete players,
# so the consolidation instead carries the per-session reasons it merged
# anyway. Set once by `RankingConsolidationBuilder`, never recomputed.
class RankingConsolidation < ApplicationRecord
  belongs_to :assessment_definition
  belongs_to :created_by, class_name: "User", optional: true

  has_many :consolidation_sessions,
           class_name: "RankingConsolidationSession",
           dependent: :destroy,
           inverse_of: :ranking_consolidation
  has_many :assessment_sessions, through: :consolidation_sessions
  has_many :rows,
           class_name: "RankingConsolidationRow",
           dependent: :destroy,
           inverse_of: :ranking_consolidation

  validates :assessment_definition, presence: true

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
end
