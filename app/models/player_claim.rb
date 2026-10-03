# A reviewable request to associate one existing PlayerProfile with a Person.
# Claiming changes only the profile's person_id; profile identity and all domain
# history remain attached to the same profile row.
class PlayerClaim < ApplicationRecord
  STATUSES = %w[pending approved rejected cancelled].freeze

  belongs_to :player_profile
  belongs_to :person
  belongs_to :initiated_by_person, class_name: "Person"
  belongs_to :reviewed_by_person, class_name: "Person", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :reviewed_at, presence: true, if: -> { %w[approved rejected].include?(status) }
  validates :reviewed_by_person, presence: true, if: -> { %w[approved rejected].include?(status) }
  validates :rejection_reason, presence: true, if: -> { status == "rejected" }
  validates :player_profile_id, uniqueness: { conditions: -> { where(status: "pending") },
                                             message: "already has a pending claim" },
            if: -> { status == "pending" }

  scope :pending, -> { where(status: "pending") }

  def pending? = status == "pending"

  def summary(include_profile_name: false)
    result = {
      id: id,
      player_profile_id: player_profile_id,
      person_id: person_id,
      status: status,
      created_at: created_at,
      reviewed_at: reviewed_at
    }
    result[:player_name] = player_profile.full_name if include_profile_name
    result
  end
end
