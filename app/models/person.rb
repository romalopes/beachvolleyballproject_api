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
#   * at most one PlayerProfile per Person
#   * at most one CoachProfile per Person
#
# Duplicate records are never hard-deleted: when two Person records describe
# the same individual, one is marked `merged` and points at the canonical
# record via `merged_into_id`.
class Person < ApplicationRecord
  STATUSES = %w[active archived merged].freeze
  CREATION_SOURCES = %w[signup coach_created player_created system].freeze

  has_one :account, foreign_key: :person_id, inverse_of: :person, dependent: :restrict_with_error
  has_one :player_profile, dependent: :destroy
  has_one :coach_profile, dependent: :destroy
  has_many :person_aliases, dependent: :destroy

  belongs_to :merged_into, class_name: "Person", optional: true
  has_many :merged_from, class_name: "Person", foreign_key: :merged_into_id, inverse_of: :merged_into

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
      player_profile_id: player_profile&.id,
      coach_profile_id: coach_profile&.id,
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
    player_profile || build_player_profile
  end

  def coach_profile_or_build
    coach_profile || build_coach_profile
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