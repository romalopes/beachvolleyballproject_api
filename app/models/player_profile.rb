# Player-specific characteristics of a Person.
#
# This is a domain descriptor, not an authorization role and not an
# authentication record: contact and credential data live on Person/Account.
class PlayerProfile < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :person

  # `update_only: true` is essential: for a has_one, Rails otherwise *replaces*
  # the person instead of updating it whenever the nested hash carries no id,
  # which would silently create a second identity on every contact-detail edit.
  # With update_only the existing person is updated in place, and a profile
  # created without one still builds a new person.
  accepts_nested_attributes_for :person, allow_destroy: false, update_only: true

  has_many :training_session_participants, dependent: :destroy, inverse_of: :player_profile

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
  def player_profile_id
    id
  end

  # Number of training sessions this player has been invited to. Part of the
  # player-detail payload (training history); callers should eager load
  # training_session_participants to avoid an extra query.
  def training_session_count
    training_session_participants.size
  end

  def metadata
    {
      id: id,
      player_profile_id: player_profile_id,
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
