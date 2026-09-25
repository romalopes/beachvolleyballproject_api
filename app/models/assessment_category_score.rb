# What the coach scored for one configured category of an applied definition.
#
# The typed entry lives here, per category — a coach may enter 1–5 for one area
# and 1–100 for another — while the parent Assessment stores only the derived
# weighted aggregate. The children are inputs; the parent is the result.
#
# Saving a row recomputes the parent's aggregate so `assessments.score` is never
# stale, and an incomplete set computes to *nil* rather than to a partial total:
# a half-scored assessment must not read as a finished one.
class AssessmentCategoryScore < ApplicationRecord
  belongs_to :assessment
  belongs_to :assessment_category

  # The criterion inside the area this row scores, when a criteria layer is in
  # use (plan S5). NULL — every row today — means "this row is the whole area",
  # which is what keeps a category carrying exactly one number and normalisation
  # an identity (D11). The column exists ahead of its use so a later phase fills
  # it in without another migration to this table.
  belongs_to :criterion, optional: true

  # Same virtual-input contract as Assessment#value: the coach's own entry on a
  # named scale, converted through RatingScale by the controller so an illegal
  # value is a 422 the coach can act on instead of a row saved without a rating.
  attr_writer :value

  after_save :recalculate_parent_score
  after_destroy :recalculate_parent_score

  # One row per category while criteria are not in use (every row today has
  # `criterion_id` NULL); one row per criterion once they are. The two partial
  # unique indexes in `AddCriterionToAssessmentCategoryScores` say the same
  # thing in the database, which is what actually guarantees it.
  validates :assessment_category_id, uniqueness: { scope: :assessment_id },
                                     if: -> { criterion_id.nil? }
  validates :criterion_id, uniqueness: { scope: %i[assessment_id assessment_category_id] },
                           allow_nil: true

  validates :scale, presence: true, inclusion: { in: RatingScale::SCALES }
  validates :score, allow_nil: true, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100
  }
  validates :reported_value, allow_nil: true, numericality: { only_integer: true }

  validate :reported_value_exists_on_its_scale
  validate :score_matches_reported_value
  validate :criterion_belongs_to_its_category

  def value
    reported_value
  end

  def value=(entry)
    return if entry.blank?

    self.scale = scale.presence || RatingScale::DEFAULT_SCALE
    number = Integer(entry, exception: false)
    return unless RatingScale.legal_value?(number, scale: scale)

    self.reported_value = number
    self.score = RatingScale.to_score(number, scale: scale)
  end

  def ten_scale
    RatingScale.to_ten(score)
  end

  def five_scale
    RatingScale.to_five(score)
  end

  def score_label
    RatingScale.describe(score)
  end

  def rated?
    score.present?
  end

  def metadata
    {
      id: id,
      assessment_category_id: assessment_category_id,
      criterion_id: criterion_id,
      criterion: criterion ? criterion.metadata : nil,
      label: assessment_category.label,
      source_type: assessment_category.source_type,
      weight: assessment_category.weight,
      position: assessment_category.position,
      score: score,
      reported_value: reported_value,
      scale: scale,
      ten_scale: ten_scale,
      five_scale: five_scale,
      score_label: score_label,
      notes: notes
    }
  end

  private

  def recalculate_parent_score
    assessment&.recalculate_weighted_score!
  end

  # A rating is only meaningful on the scale it was entered on.
  def reported_value_exists_on_its_scale
    return if reported_value.nil?
    return if RatingScale.legal_value?(reported_value, scale: scale)

    errors.add(:reported_value, "is not a value on the #{scale.presence || 'chosen'} scale")
  end

  # The canonical score and the typed value are a pair and must agree, exactly
  # as they do on the parent for a legacy single-rubric row.
  def score_matches_reported_value
    return if score.nil? || reported_value.nil? || scale.blank?
    return unless RatingScale.legal_value?(reported_value, scale: scale)
    return if score == RatingScale.to_score(reported_value, scale: scale)

    errors.add(:score, "does not match the reported value and scale")
  end

  # A criterion may only score the area it was configured under. This is a
  # cross-row rule that nothing else enforces, so it is checked from the moment
  # the column exists rather than when a criteria UI first gets it wrong.
  def criterion_belongs_to_its_category
    return if criterion_id.nil?
    return if criterion&.assessment_category_id == assessment_category_id

    errors.add(:criterion, "must belong to the category it scores")
  end
end
