class AssessmentSession < ApplicationRecord
  STATUSES = %w[draft published withdrawn].freeze

  belongs_to :assessment_definition
  belongs_to :coach_profile
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :group, optional: true

  has_many :participants,
           class_name: "AssessmentSessionParticipant",
           dependent: :destroy,
           inverse_of: :assessment_session
  has_many :assessments, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :assessment_definition, :coach_profile, presence: true
  validate :definition_must_be_active, on: :create
  validate :published_at_must_be_present, if: :published?

  scope :ordered, -> { order(scheduled_on: :desc, created_at: :desc) }

  def draft?
    status == "draft"
  end

  def published?
    status == "published"
  end

  def withdrawn?
    status == "withdrawn"
  end

  def included_participants
    participants.included
  end

  private

  def definition_must_be_active
    return if assessment_definition&.status == "active"

    errors.add(:assessment_definition, "must be active")
  end

  def published_at_must_be_present
    errors.add(:published_at, "must be present when publishing") if published_at.blank?
  end
end
