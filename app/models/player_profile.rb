# Player-specific characteristics of a Person.
#
# This is a domain descriptor, not an authorization role and not an
# authentication record: contact and credential data live on Person/Account.
class PlayerProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :person

  has_many :training_session_participants, dependent: :destroy, inverse_of: :player_profile

  accepts_nested_attributes_for :person, allow_destroy: false

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    person.full_name
  end

  def account_status
    person.account ? "connected" : "profile_only"
  end

  def metadata
    {
      id: id,
      player_profile_id: id,
      person_id: person_id,
      preferred_position: preferred_position,
      level: level,
      status: status,
      full_name: full_name,
      account_status: account_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end