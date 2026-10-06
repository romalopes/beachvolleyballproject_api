class PlayerClaimInvitationService
  class InvitationError < StandardError; end

  EXPIRATION = PlayerClaimInvitation::DEFAULT_EXPIRATION
  INVALID_MESSAGE = "Invitation is invalid, expired, revoked, or already used".freeze

  # `invitee_email` is optional. When present it is stored (normalized) and the
  # invitation can only be redeemed by a verified Account holding that address.
  def self.issue!(player_profile:, created_by_account:, invitee_email: nil)
    raw_token = SecureRandom.urlsafe_base64(32)
    invitation = PlayerClaimInvitation.transaction do
      player_profile.with_lock do
        raise InvitationError, INVALID_MESSAGE unless player_profile.account_id.nil? && player_profile.status == "active"
        raise InvitationError, "An authenticated creator Account is required" unless created_by_account

        now = Time.current
        player_profile.player_claim_invitations.active.each do |prior|
          if prior.expires_at <= now
            prior.update!(status: "expired")
          else
            prior.update!(status: "revoked", revoked_at: now)
          end
        end

        player_profile.player_claim_invitations.create!(
          created_by_account: created_by_account,
          token_digest: digest(raw_token),
          invitee_email: invitee_email,
          expires_at: now + EXPIRATION,
          status: "active"
        )
      end
    end

    [ invitation, raw_token ]
  end

  def self.redeem!(raw_token:, account:)
    raise InvitationError, INVALID_MESSAGE if raw_token.blank? || account.nil?
    user = account.user

    invitation = PlayerClaimInvitation.find_by(token_digest: digest(raw_token))
    raise InvitationError, INVALID_MESSAGE unless invitation
    profile = PlayerProfile.find_by(id: invitation.player_profile_id)
    raise InvitationError, INVALID_MESSAGE unless profile

    claim = nil
    PlayerClaimInvitation.transaction do
      profile.with_lock do
        invitation.with_lock do
          raise InvitationError, INVALID_MESSAGE unless invitation.status == "active"

          # An address-restricted invitation is refused for anyone else, and the
          # failure is the same generic message as an invalid token so the
          # endpoint never reveals that a given address was invited.
          raise InvitationError, INVALID_MESSAGE unless invitation.redeemable_by?(user)

          if invitation.expires_at <= Time.current
            invitation.update!(status: "expired")
            next
          end

          raise InvitationError, INVALID_MESSAGE unless profile.account_id.nil? && profile.status == "active"

          # Keep the Phase 3 approval step: possession of an invite authorizes a
          # claim request, but never silently links a profile without approval.
          claim = PlayerClaimService.request!(
            player_profile: profile,
            account: account
          )
          invitation.update!(status: "used", used_at: Time.current, used_by_account: account)
        end
      end
    end

    raise InvitationError, INVALID_MESSAGE unless claim

    claim
  rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid
    raise InvitationError, INVALID_MESSAGE
  end

  def self.revoke!(invitation:)
    PlayerClaimInvitation.transaction do
      invitation.with_lock do
        raise InvitationError, INVALID_MESSAGE unless invitation.status == "active"

        if invitation.expires_at <= Time.current
          invitation.update!(status: "expired")
          next
        end

        invitation.update!(status: "revoked", revoked_at: Time.current)
      end
    end
    invitation
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest
end
