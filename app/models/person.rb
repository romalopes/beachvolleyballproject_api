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

  scope :active, -> { where(status: "active") }
  # Records used by identity resolution: merged people are excluded from
  # canonical lookups but remain queryable through `merged_into_id`.
  scope :canonical, -> { where(status: [ "active", "archived" ]) }

  def full_name
    [ first_name, last_name ].compact.join(" ")
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

  def date_of_birth_cannot_be_in_the_future
    return if date_of_birth.blank?

    errors.add(:date_of_birth, "cannot be in the future") if date_of_birth > Date.current
  end

  def cannot_merge_into_self
    errors.add(:merged_into, "cannot be the same person") if merged_into_id.present? && merged_into_id == id
  end
end