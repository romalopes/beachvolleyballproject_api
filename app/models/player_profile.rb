# Player-specific characteristics of a Person.
#
# This is a domain descriptor, not an authorization role and not an
# authentication record: contact and credential data live on Person/Account.
class PlayerProfile < ApplicationRecord
  include ProfileArchiveLifecycle

  STATUSES = %w[active archived].freeze

  # Visibility dimension (soft variant, same vocabulary as TrainingSession):
  #   * shared  — the normal case: every training manager sees the player in
  #     the catalogue;
  #   * private — hidden from other coaches' lists and detail, so a coach can
  #     keep a player to themselves. Curators and admins still see everything,
  #     and the flag never blocks scheduling: any coach can add any player to
  #     any session. Soft means *presentation*, not authorization — the only
  #     hard ownership rule is that the visibility switch itself may be flipped
  #     only by the owner or an admin.
  VISIBILITIES = %w[shared private].freeze

  # `created_by` is the owner recorded at creation: the FK is stamped from the
  # authenticated request (see the create actions), and never accepted from
  # the client — mass-assignment from `player_params`/`coach_params` does not
  # include it, so neither create nor update can set it from the payload.
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :created_by_account, class_name: "Account", optional: true
  belongs_to :merged_into_profile, class_name: "PlayerProfile", optional: true
  belongs_to :merged_by_account, class_name: "Account", optional: true
  has_many :merged_profiles, class_name: "PlayerProfile", foreign_key: :merged_into_profile_id, dependent: :restrict_with_error
  belongs_to :person, optional: true
  has_many :player_claim_invitations, dependent: :restrict_with_error
  # Unified claim workflow (Phase 18). The legacy association above is retained
  # for one release so existing callers keep working.
  has_many :claim_invitations, as: :claimable, dependent: :restrict_with_error

  # `update_only: true` is essential: for a has_one, Rails otherwise *replaces*
  # the person instead of updating it whenever the nested hash carries no id,
  # which would silently create a second identity on every contact-detail edit.
  # With update_only the existing person is updated in place, and a profile
  # created without one still builds a new person.
  accepts_nested_attributes_for :person, allow_destroy: false, update_only: true

  has_many :training_session_participants, dependent: :restrict_with_error, inverse_of: :player_profile
  has_many :assessment_session_participants, dependent: :restrict_with_error, inverse_of: :player_profile
  has_many :ranking_consolidation_rows, dependent: :restrict_with_error
  has_many :player_claims, dependent: :restrict_with_error

  # Group membership is a roster entry, not evidence, and it is keyed on Person
  # (plan §2.2) rather than on this profile — so a squad can hold somebody who
  # never registered as a player. The profile reaches its groups through the
  # Person it belongs to; there is no longer a join row owned by the profile, and
  # so nothing here to cascade. `GroupMembership` belongs to the Person, which is
  # what gets destroyed with it.
  has_many :groups, through: :person

  # Assessments are the player's coaching history, so a profile may never be
  # destroyed while they exist: the row is the evidence a coach recorded, and
  # history that can vanish is history nobody can trust. Profiles leave the
  # catalogue by becoming `archived` instead of being deleted (see the
  # archive-not-delete rule), so this only guards a mistake.
  has_many :assessments, dependent: :restrict_with_error

  # Who coaches this player, and who has coached them before. The join is a
  # period (see PlayerCoach), and `restrict_with_error` rather than `:destroy` for
  # the same reason assessments use it: a period of coaching is history somebody
  # else may depend on. A profile leaves the catalogue by becoming `archived`.
  has_many :player_coaches, dependent: :restrict_with_error
  has_many :coaches, through: :player_coaches, source: :coach_profile

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, presence: true, inclusion: { in: VISIBILITIES }
  validates :display_name, presence: true, if: -> { person.nil? }
  validate :merge_state_is_consistent

  scope :active, -> { where(status: "active") }

  # Soft visibility for the catalogue: a training manager sees the shared
  # profiles plus the private ones they recorded themselves. This is the
  # project's first ownership boundary, deliberately overriding the sessions'
  # "role-based only" convention: a session created yesterday by one coach
  # must stay manageable by the others, but a player a coach keeps private
  # must not appear in another coach's list.
  scope :visible_to, ->(user) {
    return all if user.nil?
    return all if user.admin? || user.curator?

    base = where(visibility: "shared").or(ProfileOwnership.account_scope(all, user))
    # §15: belonging to the same club as a player is itself a reason to see them.
    # This is what a membership is *for* — otherwise a club's roster would have to
    # be restated as a list of coach-player grants and would drift out of date.
    peer_ids = user.person&.organisation_peer_ids
    return base if peer_ids.blank?

    base.or(where(person_id: peer_ids))
  }
  scope :owned_by, ->(user) { ProfileOwnership.account_scope(all, user) }

  def shared?
    visibility == "shared"
  end

  def private?
    visibility == "private"
  end

  # Single source of truth for "may this user see this profile?" — the
  # catalogue, the detail endpoints and any future caller must use this
  # instead of reimplementing the rules.
  def visible_to_user?(user)
    return true if shared?
    return true if user.nil?
    return true if user.admin? || user.curator?
    return true if ProfileOwnership.owned_by?(self, user)
    # §15, the single-row counterpart of the `visible_to` scope. Both must agree,
    # or a list and an item can disagree about who may see what.
    return false if person.nil? || user.person.nil?

    user.person.shares_organisation_with?(person)
  end

  def owner?(user)
    ProfileOwnership.owned_by?(self, user)
  end

  # Only the owner or an admin may flip the visibility switch.
  def visibility_change_permitted?(user)
    user.present? && (user.admin? || owner?(user))
  end

  def full_name
    person&.full_name || display_name
  end

  def merged?
    merged_into_profile_id.present?
  end

  def canonical_profile
    merged? ? merged_into_profile&.canonical_profile || merged_into_profile : self
  end

  def account_status
    person&.account_status || "profile_only"
  end

  # API-facing alias: callers address a profile by `<resource>_profile_id`
  # (training session participants already use that shape), so payloads carry
  # both the generic `id` and this domain-specific key.
  def player_profile_id
    id
  end

  # Number of training sessions this player has been invited to. Part of the
  # player-detail payload (training history); callers should eager load
  # training_session_participants to avoid an extra query.
  def training_session_count
    training_session_participants.size
  end

  # Published coaching history only: `assessment_count` and the `assessments`
  # slice on GET /players/:id count what every training manager may see.
  # Drafts and withdrawn rows are someone's working notes, not club knowledge,
  # and they leave these counters alone. Callers who feed them into a user
  # payload should still apply `visible_to(user)` first — the public status
  # is necessary but not sufficient, because the assessed player may be
  # private to the caller.
  def active_assessment_count
    assessments.active.count
  end

  # Latest published rating per rubric, newest first. "Per rubric" means the
  # category's id, or — when the rubric is free text — the text itself, so two
  # `custom_category` rows never collapse into one entry. Only one assessment
  # runs at a time here (the SPA renders a handful of rows), so the grouping
  # stays in Ruby where the reader can see it.
  def latest_rated_assessments
    assessments.active.ordered.includes(:category, :created_by, :coach_profile).group_by(&:rubric_key).map do |_, rows|
      rows.max_by(&:created_at)
    end.sort_by(&:created_at).reverse
  end

  private

  def merge_state_is_consistent
    errors.add(:merged_into_profile, "cannot be this profile") if merged_into_profile_id.present? && merged_into_profile_id == id
    if merged_into_profile_id.present? && (status != "archived" || merged_at.nil? || archived_at.nil? || merged_by_account_id.nil?)
      errors.add(:merged_into_profile, "requires archived status, timestamps, and a merging account")
    end
  end

  def metadata
    {
      id: id,
      player_profile_id: player_profile_id,
      person_id: person_id,
      preferred_position: preferred_position,
      level: level,
      status: status,
      visibility: visibility,
      created_by: created_by ? { id: created_by.id, name: created_by.name } : nil,
      full_name: full_name,
      account_status: account_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
