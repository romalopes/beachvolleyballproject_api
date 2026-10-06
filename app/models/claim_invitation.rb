# A single-use invitation that lets one human attach themselves to an identity the
# club already recorded.
#
# This replaces two near-duplicate models. `PlayerClaimInvitation` attached an
# unlinked PlayerProfile to a Person; `PersonAccountInvitation` attached a login
# Account to an accountless Person. Both had the same token digest, expiry,
# revocation and one-active-per-subject rule, and disagreed about who the issuer
# is. One polymorphic subject replaces both.
#
#   claimable_type "PlayerProfile" -> the profile links to an Account
#   claimable_type "CoachProfile"  -> the profile links to an Account
#
# A verified exact-email match permits immediate linking, whether the link was
# emailed by the application or shared manually. A profile invitation without a
# specific recipient email remains a request for staff review.
class ClaimInvitation < ApplicationRecord
  STATUSES = %w[active used revoked expired declined].freeze
  DEFAULT_EXPIRATION = 7.days
  SUBJECT_TYPES = %w[PlayerProfile CoachProfile].freeze

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
  validates :declined_at, presence: true, if: -> { status == "declined" }

  scope :active, -> { where(status: "active") }

  def effective_status(now: Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  # A verified exact-email match is sufficient proof even when staff copied
  # the link manually instead of using the delivery service.
  def verified_email_match?(user)
    invitee_email.present? && user&.email_address.to_s.strip.downcase == invitee_email && user.email_verified?
  end

  def summary(include_claimable_name: false)
    {
      id: id,
      claimable_type: claimable_type,
      claimable_id: claimable_id,
      # Retained so an existing client reading the player key keeps working.
      player_profile_id: claimable_type == "PlayerProfile" ? claimable_id : nil,
      invitee_email: invitee_email,
      emailed_at: emailed_at,
      # Kept for API compatibility. Delivery telemetry no longer controls
      # authorization; an exact verified email match is the proof.
      auto_approvable: invitee_email.present?,
      status: effective_status,
      expires_at: expires_at,
      used_at: used_at,
      revoked_at: revoked_at,
      declined_at: declined_at,
      created_at: created_at
    }.tap { |payload| payload[:claimable_name] = claimable.respond_to?(:full_name) ? claimable.full_name : ClaimSubject.for(claimable).label if include_claimable_name }
  end
end
