# Coach-specific characteristics of an Account.
#
# A CoachProfile describes an Account's volleyball role.
# Application permissions remain role-based on the User (see Role/UserRole):
# being a coach in the domain does not by itself grant administrative access.
class CoachProfile < ApplicationRecord
  include ProfileArchiveLifecycle

  STATUSES = %w[active archived].freeze

  # Visibility dimension (soft variant, same vocabulary as TrainingSession and
  # PlayerProfile): `shared` is the normal catalogue entry; `private` hides the
  # coach from other coaches' lists and detail while curators and admins still
  # see everything, and the flag never blocks scheduling. The only hard
  # ownership rule is that the switch itself may be flipped only by the owner
  # or an admin.
  VISIBILITIES = %w[shared private].freeze

  # Who recorded the coach (see PlayerProfile#created_by: the owner is stamped
  # at creation, never accepted from client params).
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :created_by_account, class_name: "Account", optional: true
  # Coaches can also be recorded before they have an Account.
  belongs_to :account, optional: true
  belongs_to :merged_into_profile, class_name: "CoachProfile", optional: true
  belongs_to :merged_by_account, class_name: "Account", optional: true
  has_many :merged_profiles, class_name: "CoachProfile", foreign_key: :merged_into_profile_id, dependent: :restrict_with_error
  # A coach recorded with only a display name can claim their profile later,
  # exactly as a player can.
  has_many :claim_invitations, as: :claimable, dependent: :restrict_with_error
  has_many :organisation_memberships, as: :memberable, dependent: :restrict_with_error
  has_many :player_claims, as: :claimable, dependent: :restrict_with_error
  has_many :assessment_sessions, dependent: :restrict_with_error

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }
  before_validation :ensure_display_name
  validates :display_name, presence: true
  validate :merge_state_is_consistent

  # The assessments this coach recorded. See PlayerProfile#assessments: the rows
  # are the coach's professional record, so they outlive the profile — which is
  # archived rather than deleted anyway.
  has_many :assessments, dependent: :restrict_with_error

  # Who this coach coaches, and who they coached before. See PlayerProfile#player_coaches
  # for why the rows outlive the profile: a period of coaching is the context that
  # makes a past assessment explicable. Ending one sets `end_date`; it is never
  # deleted, and a resumed relationship is a new period.
  has_many :player_coaches, dependent: :restrict_with_error
  has_many :players, through: :player_coaches, source: :player_profile

  scope :active, -> { where(status: "active") }

  # See PlayerProfile.visible_to: soft visibility for the catalogue — shared
  # profiles plus the private ones recorded by this user; curators and admins
  # see everything.
  scope :visible_to, ->(user) {
    return all if user.nil?
    return all if user.admin? || user.curator?

    where(visibility: "shared").or(ProfileOwnership.account_scope(all, user))
  }
  scope :owned_by, ->(user) { ProfileOwnership.account_scope(all, user) }

  def shared?
    visibility == "shared"
  end

  def private?
    visibility == "private"
  end

  # See PlayerProfile#visible_to_user?.
  def visible_to_user?(user)
    ProfilePolicy.new(actor: user, profile: self).view?
  end

  def owner?(user)
    ProfileOwnership.owned_by?(self, user)
  end

  # Only the owner or an admin may flip the visibility switch.
  def visibility_change_permitted?(user)
    user.present? && (user.admin? || owner?(user))
  end

  def full_name = display_name.presence || account&.full_name

  def merged?
    merged_into_profile_id.present?
  end

  def canonical_profile
    merged? ? merged_into_profile&.canonical_profile || merged_into_profile : self
  end

  def account_status = account_id.present? ? "connected" : "profile_only"

  # API-facing alias: callers address a profile by `<resource>_profile_id`
  # (training session participants already use that shape), so payloads carry
  # both the generic `id` and this domain-specific key.
  def coach_profile_id
    id
  end

  # Published rows attributed to this coach: the number every training manager
  # may see on GET /coaches/:id. Drafts and withdrawn rows are working notes,
  # not club knowledge, so they leave the counter alone (see
  # PlayerProfile#active_assessment_count for the same reasoning).
  def assessments_recorded_count
    assessments.active.count
  end

  # The most recent published ratings this coach recorded, newest first — the
  # "recent slice" of the coach-detail payload. Rows carry Assessment#metadata,
  # the same shape the assessments endpoints serialize.
  def recent_assessments
    assessments.active.ordered
               .includes(:category, :created_by, :coach_profile, player_profile: :account)
               .limit(5)
  end

  def metadata
    {
      id: id,
      coach_profile_id: coach_profile_id,
      display_name: display_name,
      coaching_level: coaching_level,
      qualifications: qualifications,
      status: status,
      visibility: visibility,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      full_name: full_name,
      account_status: account_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def ensure_display_name
    return if display_name.present?

    self.display_name = account&.full_name.presence
  end

  def merge_state_is_consistent
    errors.add(:merged_into_profile, "cannot be this profile") if merged_into_profile_id.present? && merged_into_profile_id == id
    if merged_into_profile_id.present? && (status != "archived" || merged_at.nil? || archived_at.nil? || merged_by_account_id.nil?)
      errors.add(:merged_into_profile, "requires archived status, timestamps, and a merging account")
    end
  end
end
