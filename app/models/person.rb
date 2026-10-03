# The domain identity of a real-world individual.
#
# Person is intentionally decoupled from authentication: an Account may be
# attached later (or never), and volleyball records — training participation,
# assessments, tournament results — always reference a Person (through its
# profiles) so history survives account creation, claiming and consolidation.
#
# A Person may simultaneously be a player and a coach (PlayerProfile +
# CoachProfile), or neither. The invariants are:
#   * at most one Account per Person
#   * any number of PlayerProfiles and CoachProfiles per Person
#
# Duplicate records are never hard-deleted: when two Person records describe
# the same individual, one is marked `merged` and points at the canonical
# record via `merged_into_id`.
class Person < ApplicationRecord
  STATUSES = %w[active archived merged].freeze
  CREATION_SOURCES = %w[signup coach_created player_created system].freeze

  has_one :account, foreign_key: :person_id, inverse_of: :person, dependent: :restrict_with_error
  has_many :player_profiles, dependent: :restrict_with_error, inverse_of: :person
  has_many :coach_profiles, dependent: :restrict_with_error, inverse_of: :person
  # Legacy singular associations remain read-only conveniences for callers that
  # have not yet gained an explicit coaching/player context selector.
  has_one :player_profile, -> { order(:id) }, inverse_of: :person
  has_one :coach_profile, -> { order(:id) }, inverse_of: :person
  # Transitional singular readers keep older API and authorization paths
  # working while callers migrate to an explicit profile selection.
  def build_player_profile(attributes = {}) = player_profiles.build(attributes)
  def build_coach_profile(attributes = {}) = coach_profiles.build(attributes)
  def create_player_profile!(attributes = {}) = player_profiles.create!(attributes)
  def create_coach_profile!(attributes = {}) = coach_profiles.create!(attributes)
  has_many :person_aliases, dependent: :destroy

  # Squad rosters, keyed on Person (§2.2) — the same reason organisation
  # memberships are. `restrict_with_error` rather than `:destroy`: a squad row is
  # a roster an assessment session was run against, and §2.5 requires membership
  # history to outlive the people in it. A person is removed from squads by ending
  # the membership, not by deleting them.
  has_many :group_memberships, dependent: :restrict_with_error
  has_many :groups, through: :group_memberships

  # Memberships are the *only* place a person's place in an organisation is
  # recorded, and they are keyed on Person so an accountless person — a committee
  # member, a parent, a volunteer coach — can belong to a club too.
  has_many :organisation_memberships, dependent: :destroy
  has_many :organisations, through: :organisation_memberships
  accepts_nested_attributes_for :organisation_memberships, allow_destroy: true, reject_if: :all_blank

  belongs_to :merged_into, class_name: "Person", optional: true
  belongs_to :merged_by, class_name: "User", optional: true
  has_many :merged_from, class_name: "Person", foreign_key: :merged_into_id, inverse_of: :merged_into
  has_many :consolidations_as_source, class_name: "PersonConsolidation", foreign_key: :source_person_id, dependent: :restrict_with_error
  has_many :consolidations_as_canonical, class_name: "PersonConsolidation", foreign_key: :canonical_person_id, dependent: :restrict_with_error

  belongs_to :created_by, class_name: "User", optional: true

  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, length: { maximum: 50 }
  validates :phone, length: { maximum: 30 }, allow_nil: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :creation_source, presence: true, inclusion: { in: CREATION_SOURCES }
  validate :date_of_birth_cannot_be_in_the_future
  validate :cannot_merge_into_self

  # A rename must not lose the previous spelling: coaches search by the name
  # they know, and a person who changes their name would otherwise stop being
  # findable. Recorded here (not in the controllers) because a person can be
  # renamed from the player/coach API *and* from their own account page.
  after_update :remember_previous_name, if: :saved_change_to_name?

  scope :active, -> { where(status: "active") }
  # Records used by identity resolution: merged people are excluded from
  # canonical lookups but remain queryable through `merged_into_id`.
  scope :canonical, -> { where(status: [ "active", "archived" ]) }

  # Ids of the organisations this person is *currently* an active member of. The
  # basis for every organisation-scoped visibility rule, so it is one query and one
  # definition rather than the same join restated in each policy.
  def active_organisation_ids
    organisation_memberships.active.pluck(:organisation_id)
  end

  def member_of?(organisation)
    organisation_memberships.active.exists?(organisation_id: organisation.id)
  end

  def manages?(organisation)
    organisation_memberships.active.manageable.exists?(organisation_id: organisation.id)
  end

  # True when this person and `other` are active members of at least one of the
  # *same* organisations. Deliberately an exact-match test and not an ancestor one:
  # a national federation member does not thereby see a private assessment
  # belonging to a club at the bottom of its tree.
  # The people who are peers of this one: everyone who is an active member of at
  # least one of the *same* organisations. §15 makes these mutually visible.
  #
  # Deliberately not the hierarchy. Sitting above a club in the tree is not the
  # same as being in it, and a national federation's roster is not a union of its
  # clubs' rosters.
  def organisation_peer_ids
    ids = active_organisation_ids
    return [] if ids.empty?

    Person.joins(:organisation_memberships)
         .where(organisation_memberships: { organisation_id: ids, status: "active" })
         .distinct
         .pluck(:id)
  end

  def shares_organisation_with?(other)
    return false if other.nil?

    ids = active_organisation_ids
    return false if ids.empty?

    other.active_organisation_ids.any? { |id| ids.include?(id) }
  end

  def full_name
    [ first_name, last_name ].compact.join(" ")
  end

  # Whether this person can authenticate ("connected") or exists only as a
  # staff-recorded profile ("profile_only"). Single source of truth for the
  # player/coach profiles and for the identity search payload.
  def account_status
    account ? "connected" : "profile_only"
  end

  # Compact identity payload shared by the identity-search endpoint
  # (/api/v1/people) and the possible-duplicate suggestions returned when a
  # player or coach is created. Callers should eager load account and the
  # profiles to avoid N+1 queries.
  def identity_summary
    {
      id: id,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      email: email,
      phone: phone,
      date_of_birth: date_of_birth,
      creation_source: creation_source,
      account_status: account_status,
      # Keep the singular keys during the API transition for existing clients;
      # new clients should use the complete profile ID lists.
      player_profile_id: player_profiles.first&.id,
      player_profile_ids: player_profiles.map(&:id),
      coach_profile_id: coach_profiles.first&.id,
      coach_profile_ids: coach_profiles.map(&:id),
      # Alternate names are not identity evidence, but they are how a coach
      # recognises someone ("Ah, Pedro — I knew him as Peter").
      aliases: person_aliases.map(&:full_name)
    }
  end

  def merged?
    status == "merged"
  end

  # Follows the merge chain to the canonical Person. Returns self when not
  # merged.
  def canonical_person
    merged? ? merged_into&.canonical_person || self : self
  end

  # Convenience accessors that create (but do not save) the profile when
  # missing, so callers can do `person.build_player_profile`.
  def player_profile_or_build
    player_profiles.first || player_profiles.build
  end

  def coach_profile_or_build
    coach_profiles.first || coach_profiles.build
  end

  private

  # True when first or last name changed in the update that just happened.
  def saved_change_to_name?
    saved_change_to_first_name? || saved_change_to_last_name?
  end

  # Keeps the name the person was known by. Skips blanks, no-ops, and names
  # already recorded (so renaming back and forth does not stack duplicates).
  def remember_previous_name
    previous = [
      saved_change_to_first_name? ? saved_change_to_first_name.first : first_name,
      saved_change_to_last_name? ? saved_change_to_last_name.first : last_name
    ].compact.join(" ").strip

    return if previous.blank? || previous == full_name
    return if person_aliases.any? { |alias_record| alias_record.full_name == previous }

    person_aliases.create!(full_name: previous, alias_type: "previous_name")
  end

  def date_of_birth_cannot_be_in_the_future
    return if date_of_birth.blank?

    errors.add(:date_of_birth, "cannot be in the future") if date_of_birth > Date.current
  end

  def cannot_merge_into_self
    errors.add(:merged_into, "cannot be the same person") if merged_into_id.present? && merged_into_id == id
  end
end
