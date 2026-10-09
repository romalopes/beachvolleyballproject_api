# One Account's membership of a Group.
#
# Keyed on Account rather than PlayerProfile. An account may be staff-recorded
# and unclaimed, so a squad can contain somebody without a login or profile.
#
# `status` is `pending` / `active` / `ended`. `pending` is a self-service join
# request awaiting the group's review (see `Group#approval_required?`) — it
# grants nothing until an approver activates it. It deliberately does *not*
# carry the invited / confirmed / attended vocabulary the previous version of
# this model rejected, and that reasoning still holds: attendance is evidence about one
# session, so it belongs on the session that observed it, not on the roster where
# it would be a stale opinion. Leaving a squad, though, is a fact about the roster
# itself, and §2.5 requires it to be recorded rather than deleted.
class GroupMembership < ApplicationRecord
  ROLES = %w[owner coach member].freeze
  STATUSES = %w[pending active ended].freeze

  belongs_to :group, inverse_of: :group_memberships
  belongs_to :account

  validates :account_id, uniqueness: { scope: :group_id }
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :left_at_belongs_to_an_ended_membership
  validate :owner_cannot_leave

  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :ended, -> { where(status: "ended") }
  # The one active owner, if there is one. The database guarantees at most one
  # (a partial unique index); this is how that fact is read back.
  scope :owners, -> { where(role: "owner", status: "active") }
  scope :ordered, -> { order(:id) }

  def owner?
    role == "owner" && status == "active"
  end

  def ended?
    status == "ended"
  end

  def pending?
    status == "pending"
  end

  def activate!
    update!(status: "active", joined_at: Time.current, left_at: nil)
  end

  def player_name
    account.full_name
  end

  # Ends the membership rather than destroying it (§2.5). Called from the model so
  # the rule holds however the caller chose to leave.
  def end_membership!(at: Time.current)
    update!(status: "ended", left_at: at)
  end

  private

  def owner_cannot_leave
    if persisted? && role_in_database == "owner" && status_in_database == "active" && status != "active"
      errors.add(:status, "cannot end the group owner's membership")
    end
  end

  # `left_at` belongs to `ended` and to nothing else, so the two can never
  # disagree about whether somebody actually left. Mirrors
  # organisation_memberships (§4.5); the database carries the same constraint.
  def left_at_belongs_to_an_ended_membership
    return if left_at.nil?
    return if status == "ended"

    errors.add(:left_at, "can only be set when the membership has ended")
  end
end
