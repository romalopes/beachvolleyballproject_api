# Coach-specific characteristics of a Person.
#
# A CoachProfile describes what the person is in the volleyball domain.
# Application permissions remain role-based on the User (see Role/UserRole):
# being a coach in the domain does not by itself grant administrative access.
class CoachProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :person

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    person.full_name
  end
end