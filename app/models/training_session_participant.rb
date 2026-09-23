# A PlayerProfile's participation in a Training Session, including
# attendance.
#
# This is the join between the shared schedule and the domain identity: it
# exists so that a player without an account can be a participant and keep
# attendance history, and so that visibility can later be scoped by
# participation (see TrainingSession.visible_to).
class TrainingSessionParticipant < ApplicationRecord
  STATUSES = %w[invited confirmed declined attended absent].freeze

  belongs_to :training_session, inverse_of: :training_session_participants
  belongs_to :player_profile, inverse_of: :training_session_participants

  has_one :person, through: :player_profile

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :player_profile_id, uniqueness: { scope: :training_session_id }
  validate :training_session_is_not_cancelled, on: :create

  scope :ordered, -> { order(:id) }

    # Display helpers for the API payload.
  def player_name
    person&.full_name
  end

  # Human-readable label for the participant's attendance/status.
  def status_label
    status.to_s.capitalize
  end

  # Whether the participating player has an Account. Used by clients to show
  # "Account connected" vs "Profile only".
  def account_connected?
    person&.account.present?
  end

  # Same fact without the predicate suffix, so the serialized payload key is
  # `account_connected` (clients are JavaScript, where `?` keys are awkward).
  def account_connected
    account_connected?
  end

  private

  # Once a session is cancelled, no new participants can be added; existing
  # rows stay as historical attendance records.
  def training_session_is_not_cancelled
    errors.add(:training_session, "is cancelled") if training_session&.cancelled?
  end
end