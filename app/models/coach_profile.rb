# Coach-specific characteristics of a Person.
#
# A CoachProfile describes what the person is in the volleyball domain.
# Application permissions remain role-based on the User (see Role/UserRole):
# being a coach in the domain does not by itself grant administrative access.
class CoachProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :person

  # See PlayerProfile: update_only keeps a has_one update from replacing the
  # person (and creating a second identity) when no id is sent.
  accepts_nested_attributes_for :person, allow_destroy: false, update_only: true

  validates :person_id, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def full_name
    person.full_name
  end

  def account_status
    person.account_status
  end

  # API-facing alias: callers address a profile by `<resource>_profile_id`
  # (training session participants already use that shape), so payloads carry
  # both the generic `id` and this domain-specific key.
  def coach_profile_id
    id
  end

  def metadata
    {
      id: id,
      coach_profile_id: coach_profile_id,
      person_id: person_id,
      coaching_level: coaching_level,
      qualifications: qualifications,
      status: status,
      full_name: full_name,
      account_status: account_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end
end
