# One person's membership of one organisation.
#
# Keyed on Account. An Account may exist before it has a login User, allowing a
# club to record a parent, committee member or volunteer before they sign up.
#
# `role` and the Person's own volleyball roles are different facts and are never
# derived from one another. A national coach can be an ordinary `member` of one club
# and the `owner` of an academy.
#
# Membership has a lifecycle rather than being deleted: someone who leaves stays on
# the record, which is what makes a historical assessment explicable years later.
# A row is only ever moved to `ended`.
class OrganisationMembership < ApplicationRecord
  ROLES = %w[owner administrator coach member].freeze
  STATUSES = %w[pending active suspended ended].freeze

  # Roles that may change who belongs to an organisation, as opposed to those that
  # only describe what a member does here. Deliberately does *not* include `coach`:
  # a coach is someone who coaches, which is not a grant over the roster.
  MANAGEMENT_ROLES = %w[owner administrator].freeze

  belongs_to :organisation
  belongs_to :account, optional: true
  belongs_to :memberable, polymorphic: true

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :memberable_type, inclusion: { in: %w[Account PlayerProfile CoachProfile] }
  validates :memberable_id, uniqueness: { scope: %i[organisation_id memberable_type],
                                           message: "is already a member of this organisation" }
  validate :ended_membership_has_left_at
  validate :one_active_owner_per_organisation

  before_validation :derive_memberable_from_account
  before_validation :stamp_lifecycle_timestamps

  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: "pending") }
  scope :ended, -> { where(status: "ended") }
  scope :current, -> { where.not(status: "ended") }
  scope :with_role, ->(role) { role.present? ? where(role: role) : all }
  scope :manageable, -> { where(role: MANAGEMENT_ROLES) }
  scope :ordered, -> { order(:role, :id) }

  def active?
    status == "active"
  end

  def ended?
    status == "ended"
  end

  # Invited but not yet accepted. Distinct from `ended` because the two mean
  # opposite things: one never arrived, the other was here and left.
  def pending?
    status == "pending"
  end

  # An invitation nobody accepted can be withdrawn outright. It records no stint,
  # so keeping it would keep nothing and removing it loses nothing — whereas
  # ending it would write a `left_at` claiming the person left a club they never
  # joined, which is precisely the fabricated history §2.5 exists to prevent.
  #
  # This is the only membership row that may be destroyed.
  def withdrawable?
    pending?
  end

  def manages?
    active? && MANAGEMENT_ROLES.include?(role)
  end

  def owner?
    role == "owner" && active?
  end

  def status_label
    status.to_s.capitalize
  end

  def role_label
    role.to_s.capitalize
  end

  def display_name
    memberable.full_name
  end

  # The move a membership makes in ordinary use. Kept here rather than in a service
  # because the two fields that change together — status, joined_at, left_at — are
  # exactly the ones a database constraint ties together.
  def activate!
    update!(status: "active", joined_at: Time.current, left_at: nil)
  end

  def end!
    update!(status: "ended", left_at: Time.current)
  end

  def metadata
    {
      id: id,
      organisation_id: organisation_id,
      account_id: account_id,
      memberable_type: memberable_type,
      memberable_id: memberable_id,
      person_name: display_name,
      role: role,
      role_label: role_label,
      status: status,
      status_label: status_label,
      joined_at: joined_at,
      left_at: left_at,
      manages: manages?,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # Existing Account memberships predate the polymorphic subject columns. Keep
  # Account writes compatible and repair an old row when it is next saved.
  def derive_memberable_from_account
    self.memberable = account if account.present? && memberable.nil?
  end

  # Joined/left timestamps follow the status rather than being set independently, so
  # the two can never contradict each other. Mirrored by a database check on
  # `left_at`.
  def stamp_lifecycle_timestamps
    if status == "active" && joined_at.blank?
      self.joined_at = Time.current
    end

    return unless status == "ended"
    return if left_at.present?

    self.left_at = Time.current
  end

  def ended_membership_has_left_at
    return unless status == "ended" && left_at.blank?

    errors.add(:left_at, "must be set when the membership ends")
  end

  # Mirrors the partial unique index, so a second owner is refused with a message
  # naming the problem rather than a raw constraint violation. The index remains the
  # real guard: this check loses to a race, the index does not.
  def one_active_owner_per_organisation
    return unless role == "owner" && status == "active"

    rival = OrganisationMembership
            .where(organisation_id: organisation_id, role: "owner", status: "active")
    rival = rival.where.not(id: id) if persisted?

    return if rival.none?

    errors.add(:role, "already has an active owner")
  end
end
