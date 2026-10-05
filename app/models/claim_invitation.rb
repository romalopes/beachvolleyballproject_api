# A single-use invitation that lets one human attach themselves to an identity the
# club already recorded.
#
# This replaces two near-duplicate models. `PlayerClaimInvitation` attached an
# unlinked PlayerProfile to a Person; `PersonAccountInvitation` attached a login
# Account to an accountless Person. Both had the same token digest, expiry,
# revocation and one-active-per-subject rule, and disagreed about who the issuer
# is. One polymorphic subject replaces both.
#
#   claimable_type "PlayerProfile" -> the profile adopts a Person
#   claimable_type "CoachProfile"  -> the profile adopts a Person
#   claimable_type "Person"        -> a login Account adopts this identity
#
# `emailed_at` decides whether redemption can auto-approve. Only an invitation the
# club actually *emailed* to the address the recipient controls counts as proof
# of delivery; a hand-copied link has no `emailed_at` and always requires staff
# review. See ClaimInvitationService#auto_approvable?.
class ClaimInvitation < ApplicationRecord
  STATUSES = %w[active used revoked expired].freeze
  DEFAULT_EXPIRATION = 7.days
  SUBJECT_TYPES = %w[PlayerProfile CoachProfile Person].freeze

  belongs_to :claimable, polymorphic: true
  belongs_to :invited_by, class_name: "User"
  belongs_to :used_by, class_name: "User", optional: true

  # Downcased and trimmed so redemption is an exact comparison rather than a
  # case-insensitive SQL lookup on every attempt.
  normalizes :invitee_email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :token_digest, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :expires_at, presence: true
  validates :invitee_email, format: { with: URI::MailTo::EMAIL_REGEXP },
                          allow_nil: true
  validates :used_at, presence: true, if: -> { status == "used" }
  validates :used_by, presence: true, if: -> { status == "used" }
  validates :revoked_at, presence: true, if: -> { status == "revoked" }

  scope :active, -> { where(status: "active") }

  def effective_status(now: Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  # True only when the invitation was genuinely delivered by email to
  # `user`'s address. Any of these failing means a human must review it.
  def delivered_to?(user)
    return false if emailed_at.nil? || invitee_email.blank?
    return false unless user&.email_address.to_s.strip.downcase == invitee_email

    user.email_verified?
  end

  def summary
    {
      id: id,
      claimable_type: claimable_type,
      claimable_id: claimable_id,
      # Retained so an existing client reading the player key keeps working.
      player_profile_id: claimable_type == "PlayerProfile" ? claimable_id : nil,
      person_id: claimable_type == "Person" ? claimable_id : nil,
      invitee_email: invitee_email,
      emailed_at: emailed_at,
      auto_approvable: emailed_at.present?,
      status: effective_status,
      expires_at: expires_at,
      used_at: used_at,
      revoked_at: revoked_at,
      created_at: created_at
    }
  end
end
