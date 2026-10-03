# A single-use bearer credential issued by the recorded coach or an admin.
# Only the SHA-256 digest is persisted; the raw token is returned once to the
# authorized creator and is never placed on the model or in audit descriptions.
class PlayerClaimInvitation < ApplicationRecord
  STATUSES = %w[active used revoked expired].freeze
  DEFAULT_EXPIRATION = 7.days

  belongs_to :player_profile
  belongs_to :created_by_person, class_name: "Person"
  belongs_to :used_by_person, class_name: "Person", optional: true

  validates :token_digest, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true
  validates :used_at, presence: true, if: -> { status == "used" }
  validates :used_by_person, presence: true, if: -> { status == "used" }
  validates :revoked_at, presence: true, if: -> { status == "revoked" }

  scope :active, -> { where(status: "active") }

  def effective_status(now: Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  def summary
    {
      id: id,
      player_profile_id: player_profile_id,
      status: effective_status,
      expires_at: expires_at,
      used_at: used_at,
      revoked_at: revoked_at,
      created_at: created_at
    }
  end
end
