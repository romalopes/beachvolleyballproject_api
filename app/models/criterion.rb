# Phase 6 (Assessment Sessions), plan S5: one scored line item inside a
# configured category — "Attack" is the weighted area, "Approach footwork" a
# criterion inside it.
#
# The table is created ahead of its use. Nothing scores against a criterion yet:
# every `assessment_category_scores` row keeps `criterion_id` NULL, which means
# "this row is the whole area", so a category still carries exactly one number
# and normalisation remains an identity (D11).
#
# The structure exists now for two reasons:
#   * a later criteria phase can be filled in without another migration to the
#     scoring tables (the partial indexes in the companion migration already
#     allow one row per criterion);
#   * the cross-row rule "a criterion must belong to the area it scores" can be
#     enforced from day one, before any UI exists that could break it.
#
# Criteria belong to the *configured category*, not the definition: §20's own
# example compares areas carrying different numbers of items, so Attack's
# criteria are not Defence's.
class Criterion < ApplicationRecord
  belongs_to :assessment_category, inverse_of: :criteria

  # A scored criterion is history. A definition that results quote is frozen
  # (D7), so a criterion cannot be dropped out from under the scores that name
  # it — the row is refused rather than silently rewriting what a coach
  # recorded.
  has_many :assessment_category_scores, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.strip.presence }

  validates :name, presence: true,
                   uniqueness: { scope: :assessment_category_id, case_sensitive: false }
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }

  def metadata
    { id: id, name: name, position: position }
  end
end
