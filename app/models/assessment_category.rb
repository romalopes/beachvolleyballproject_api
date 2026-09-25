# One configured category inside an assessment definition, and the weight it
# contributes to the aggregate.
#
# The row belongs to the *definition*, not to an assessment: `assessments` is
# the per-player result table, and a category configures the reusable template.
#
# Position is presentation order only — it never enters the calculation (the
# calculation is a sum over weights, which is order-independent). Missing
# positions are filled from the submitted array index by the controller, the
# same way training focuses do it.
class AssessmentCategory < ApplicationRecord
  belongs_to :assessment_definition
  belongs_to :category, optional: true
  belongs_to :category_custom, optional: true

  # A scored configuration is history: the definition may not drop it out from
  # under the results that already quote it.
  has_many :assessment_category_scores, dependent: :restrict_with_error

  validates :weight, presence: true,
                     numericality: { only_integer: true, greater_than: 0 }
  validates :position, presence: true,
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :category_id, uniqueness: { scope: :assessment_definition_id }, allow_nil: true
  validates :category_custom_id, uniqueness: { scope: :assessment_definition_id }, allow_nil: true

  validate :source_is_exactly_one
  validate :source_must_exist

  scope :ordered, -> { order(:position, :id) }

  def custom?
    category_custom_id.present?
  end

  # Which branch of the XOR this row sits on — serialized so the SPA never has
  # to infer it from which id happens to be null.
  def source_type
    custom? ? "custom_category" : "category"
  end

  def label
    category&.name || category_custom&.name
  end

  def metadata
    {
      id: id,
      category_id: category_id,
      category_custom_id: category_custom_id,
      weight: weight,
      position: position,
      source_type: source_type,
      label: label,
      category: category ? { id: category.id, name: category.name, slug: category.slug } : nil,
      category_custom: category_custom ? category_custom.metadata : nil
    }
  end

  private

  # Exactly one source: a standard Category XOR a custom one. The database
  # enforces the same rule; mirroring it here turns a constraint violation into
  # a message the coach can act on.
  def source_is_exactly_one
    if category_id.present? && category_custom_id.present?
      errors.add(:category_custom, "must be blank when a category is selected")
    elsif category_id.blank? && category_custom_id.blank?
      errors.add(:base, "Choose a category or a custom category")
    end
  end

  # A client-supplied id is never trusted: it must name a row that exists,
  # otherwise the foreign key would raise at save time with no usable message.
  def source_must_exist
    errors.add(:category, "must exist") if category_id.present? && !Category.exists?(category_id)
    if category_custom_id.present? && !CategoryCustom.exists?(category_custom_id)
      errors.add(:category_custom, "must exist")
    end
  end
end
