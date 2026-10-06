# A single-use bearer credential issued by the recorded coach or an admin.
# Only the SHA-256 digest is persisted; the raw token is returned once to the
# authorized creator and is never placed on the model or in audit descriptions.
class PlayerClaimInvitation < ApplicationRecord
  STATUSES = %w[active used revoked expired].freeze
  DEFAULT_EXPIRATION = 7.days

  belongs_to :player_profile
  belongs_to :created_by_account, class_name: "Account", optional: true
  belongs_to :used_by_account, class_name: "Account", optional: true

  # An invitation may be restricted to one address. Stored downcased and
  # trimmed so the redemption comparison is an exact match rather than a
  # case-insensitive SQL lookup on every redeem.
  normalizes :invitee_email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :token_digest, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true
  validates :invitee_email, format: { with: URI::MailTo::EMAIL_REGEXP },
                          allow_nil: true
  validates :used_at, presence: true, if: -> { status == "used" }
  validates :used_by_account_id, presence: true, if: -> { status == "used" }
  validates :revoked_at, presence: true, if: -> { status == "revoked" }

  scope :active, -> { where(status: "active") }

  # True when this invitation may only be redeemed by the holder of
  # invitee's email address. An invitation with no address is an open bearer
  # token, which is the only option for a placeholder profile.
  def redeemable_by?(user)
    return true if invitee_email.blank?

    user.present? && user.email_address.to_s.strip.downcase == invitee_email && user.email_verified?
  end

  def effective_status(now: Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  def summary
    {
      id: id,
      player_profile_id: player_profile_id,
      status: effective_status,
      invitee_email: invitee_email,
      expires_at: expires_at,
      used_at: used_at,
      revoked_at: revoked_at,
      created_at: created_at
    }
  end
end
