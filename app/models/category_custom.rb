# A coach-authored category that is not part of the club catalogue ("Mental
# game", "Communication").
#
# Phase 4 kept a custom rubric as free text on the assessment itself, which is
# right for a one-off observation but leaves "who may use this custom category?"
# with nothing to reference. A row with `created_by` + `visibility` makes that
# rule checkable, reusing the shared/private pair the profile-visibility work
# introduced.
class CategoryCustom < ApplicationRecord
  VISIBILITIES = %w[shared private].freeze

  belongs_to :created_by, class_name: "User", optional: true

  # An in-use custom category is edited or left alone, never silently deleted:
  # dropping it would rewrite the configuration of every definition that points
  # at it (the same reasoning as an in-use Category).
  has_many :assessment_categories, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.strip.presence }

  validates :name, presence: true,
                   uniqueness: { scope: :created_by_id, case_sensitive: false }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }

  scope :ordered, -> { order(:name, :id) }

  def shared?
    visibility == "shared"
  end

  def private?
    visibility == "private"
  end

  # May this user select this custom category in a definition?
  #
  # * oversight (curator/admin) always may — they administer the club's config;
  # * `shared` is club knowledge, so any content creator may use it;
  # * `private` belongs to its creator alone.
  def usable_by?(user)
    return false if user.nil?
    return true if Assessment.oversight?(user)
    return true if shared? && user.respond_to?(:content_manager?) && user.content_manager?

    created_by_id.present? && created_by_id == user.id
  end

  # Only the author and oversight may edit the record itself.
  def manageable_by?(user)
    return false if user.nil?

    Assessment.oversight?(user) || (created_by_id.present? && created_by_id == user.id)
  end

  def metadata
    {
      id: id,
      name: name,
      visibility: visibility,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil
    }
  end
end
