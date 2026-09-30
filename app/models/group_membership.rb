# One Person's membership of a Group.
#
# Keyed on Person rather than PlayerProfile (plan §2.2), for the same reason
# OrganisationMembership is: a squad has to be able to contain a coach, a parent
# or a volunteer who never registered as a player at all. That is not hypothetical
# — the rehearsal data's one group had a creator with no player profile, who could
# not be given an ownership row at all under the old key.
#
# `status` is only `active` / `ended`. It deliberately does *not* carry the
# invited / confirmed / attended vocabulary the previous version of this model
# rejected, and that reasoning still holds: attendance is evidence about one
# session, so it belongs on the session that observed it, not on the roster where
# it would be a stale opinion. Leaving a squad, though, is a fact about the roster
# itself, and §2.5 requires it to be recorded rather than deleted.
class GroupMembership < ApplicationRecord
  ROLES = %w[owner coach member].freeze
  STATUSES = %w[active ended].freeze

  belongs_to :group, inverse_of: :group_memberships
  belongs_to :person

  validates :person_id, uniqueness: { scope: :group_id }
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :left_at_belongs_to_an_ended_membership

  scope :active, -> { where(status: "active") }
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

  def player_name
    person&.full_name
  end

  # Ends the membership rather than destroying it (§2.5). Called from the model so
  # the rule holds however the caller chose to leave.
  def end_membership!(at: Time.current)
    update!(status: "ended", left_at: at)
  end

  private

  # `left_at` belongs to `ended` and to nothing else, so the two can never
  # disagree about whether somebody actually left. Mirrors
  # organisation_memberships (§4.5); the database carries the same constraint.
  def left_at_belongs_to_an_ended_membership
    return if left_at.nil?
    return if status == "ended"

    errors.add(:left_at, "can only be set when the membership has ended")
  end
end
