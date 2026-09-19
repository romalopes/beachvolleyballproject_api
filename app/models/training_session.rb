# A scheduled beach volleyball training.
#
# Training Sessions are shared schedule resources: `created_by` records who
# created the session (audit only) and never acts as a private ownership
# boundary. Visibility and management are role-based (see `visible_to` and
# ContentAuthorization).
#
# Focuses describe what the training works on (an existing Skill or custom
# text); drills are selected explicitly by the coach. A drill is only
# referenced through TrainingSessionDrill — its description, visual definition
# and steps always come from the Drill itself, so future Drill versioning can
# slot in without touching this model.
class TrainingSession < ApplicationRecord
  STATUSES = %w[draft scheduled cancelled completed].freeze

  # Drafts are internal working copies. Everything else belongs to the shared
  # schedule and is visible to anyone who can browse the application.
  PUBLICLY_VISIBLE_STATUSES = (STATUSES - [ "draft" ]).freeze

  belongs_to :created_by, class_name: "User", optional: true

  has_many :training_focuses, -> { order(:position, :id) },
           dependent: :destroy, inverse_of: :training_session
  has_many :training_session_drills, -> { order(:position, :id) },
           dependent: :destroy, inverse_of: :training_session
  has_many :drills, through: :training_session_drills

  # Media: the polymorphic VideoReference lets a training session carry videos
  # (e.g. a recording of the session) without a dedicated join table.
  has_many :video_references, as: :referenced, dependent: :destroy
  has_many :videos, through: :video_references

  accepts_nested_attributes_for :training_focuses, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :training_session_drills, allow_destroy: true, reject_if: :all_blank

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :ends_at_after_starts_at

  scope :ordered, -> { order(:starts_at, :id) }
  # Calendar support: only load the window being displayed.
  scope :starting_between, ->(from, to) {
    scope = all
    scope = scope.where(starts_at: from..) if from.present?
    scope = scope.where(starts_at: ..to) if to.present?
    scope
  }
  # Drafts stay private to management users; the rest is part of the shared
  # calendar. A guest (nil user) sees the shared schedule only.
  scope :visible_to, ->(user) {
    if user.respond_to?(:content_manager?) && user.content_manager?
      all
    else
      where(status: PUBLICLY_VISIBLE_STATUSES)
    end
  }

  def draft?
    status == "draft"
  end

  def scheduled?
    status == "scheduled"
  end

  def cancelled?
    status == "cancelled"
  end

  def completed?
    status == "completed"
  end

  def status_label
    status.to_s.capitalize
  end

  # Non-draft trainings belong to the shared schedule.
  def publicly_visible?
    !draft?
  end

  # Total scheduled length in minutes (the sum of the selected drills may
  # differ; this reflects the calendar block).
  def duration_minutes
    return nil if starts_at.nil? || ends_at.nil?

    ((ends_at - starts_at) / 60).round
  end

  private

  def ends_at_after_starts_at
    return if starts_at.nil? || ends_at.nil?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the start time")
  end
end
