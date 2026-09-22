# Player-specific characteristics of a Person.
#
# This is a domain descriptor, not an authorization role and not an
# authentication record: contact and credential data live on Person/Account.
class PlayerProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :person

  has_many :training_session_participants, dependent: :destroy, inverse_of: :player_profile

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    person.full_name
  end
end