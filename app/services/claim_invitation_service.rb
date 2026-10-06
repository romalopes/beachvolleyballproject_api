# Issues, redeems and revokes claim invitations for any subject kind.
#
# Redeeming an active invitation is the recipient's acceptance of the profile.
# An email-addressed invitation still requires the verified recipient account;
# an open link is a bearer invitation and links the authenticated redeemer.
class ClaimInvitationService
  class InvitationError < StandardError; end

  # Internal signal: the invitation cannot be redeemed by this caller, and
  # nothing was written. Raised inside the transaction so the rollback leaves the
  # invitation usable, then translated into `InvitationError` outside it.
  class NotRedeemable < StandardError; end
  class NeedsVerification < StandardError; end

  INVALID_MESSAGE =
    "This invitation is invalid, expired, revoked, already used, or not eligible.".freeze
  VERIFICATION_MESSAGE =
    "Verify this account's email address before accepting the invitation.".freeze

  def self.issue!(claimable:, invited_by:, invitee_email: nil)
    subject = ClaimSubject.for(claimable)
    raise InvitationError, subject.ineligibility_reason unless subject.eligible?

    unless ProfileClaimability::PROFILE_TYPES.include?(claimable.class.name) || claimable.is_a?(Person)
      raise InvitationError, "Only player and coach profiles can be invited."
    end
    raw_token = SecureRandom.urlsafe_base64(32)

    invitation = ClaimInvitation.transaction do
      claimable.with_lock do
        subject = ClaimSubject.for(claimable)
        raise InvitationError, subject.ineligibility_reason unless subject.eligible?
        address = invitee_email.presence || subject.default_email

        now = Time.current
        claimable.claim_invitations.active.each do |prior|
          if prior.expires_at <= now
            prior.update!(status: "expired")
          else
            prior.update!(status: "revoked", revoked_at: now)
          end
        end

        claimable.claim_invitations.create!(
          invited_by: invited_by,
          invitee_email: address,
          token_digest: digest(raw_token),
          expires_at: now + ClaimInvitation::DEFAULT_EXPIRATION,
          status: "active"
        )
      end
    end

    [ invitation, raw_token ]
  end

  # Returns the linked account. Staff-reviewed claims are created only through
  # the separate profile-claim workflow, never by redeeming an invitation.
  def self.redeem!(raw_token:, user:)
    raise InvitationError, INVALID_MESSAGE if raw_token.to_s.strip.empty?

    invitation = ClaimInvitation.find_by(token_digest: digest(raw_token.to_s.strip))
    raise InvitationError, INVALID_MESSAGE unless invitation

    begin
      # Set to the outcome below. Left nil when the invitation is simply not
      # usable, which is reported *after* the transaction so that marking an
      # expired invitation expired actually persists — raising from inside would
      # roll that very write back.
      outcome = nil
      ClaimInvitation.transaction do
        # One consistent lock order everywhere: subject, then invitation, then
        # user. The user row serializes two invitations racing to attach one login.
        invitation.claimable.with_lock do
          invitation.with_lock do
            user.with_lock do
              if invitation.status != "active" || invitation.expires_at <= Time.current
                invitation.update!(status: "expired") if invitation.status == "active"
                next
              end

              # Everything below writes nothing before it succeeds, so raising
              # here rolls the transaction back cleanly and leaves the invitation
              # usable for a later, legitimate attempt.
              # An address-restricted invitation is refused for anyone else, with
              # the same generic message, so the endpoint never confirms that a
              # given address was invited.
              if invitation.invitee_email.present? &&
                 user.email_address.to_s.strip.downcase != invitation.invitee_email
                raise NotRedeemable
              end

              if invitation.invitee_email.present? && !user.email_verified?
                raise NeedsVerification
              end

              # Older Users may predate Account provisioning. Keep provisioning
              # atomic with invitation acceptance; ContactDetails are created by
              # the Account model and remain independent of profile identity.
              account = user.account || Account.create!(user: user)

              subject = ClaimSubject.for(invitation.claimable)
              # The record may have been archived, cleared of its required
              # display name, or linked since issuance. Reapply the exact
              # eligibility check while holding both subject and invitation
              # locks so stale links cannot revive an ineligible record.
              raise NotRedeemable unless subject.eligible? && subject.still_unclaimed?

              outcome = auto_link!(invitation: invitation, subject: subject, account: account, user: user)
            end
          end
        end
      end
    rescue NotRedeemable
      raise InvitationError, INVALID_MESSAGE
    rescue NeedsVerification
      raise InvitationError, VERIFICATION_MESSAGE
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ClaimSubject::Ineligible
      raise InvitationError, INVALID_MESSAGE
    end

    raise InvitationError, INVALID_MESSAGE unless outcome

    outcome
  end
  def self.revoke!(invitation:)
    ClaimInvitation.transaction do
      invitation.claimable.with_lock do
        invitation.with_lock do
          raise InvitationError, INVALID_MESSAGE unless invitation.status == "active"

          if invitation.expires_at <= Time.current
            invitation.update!(status: "expired")
          else
            invitation.update!(status: "revoked", revoked_at: Time.current)
          end
        end
      end
    end
    invitation
  end

  # A recipient may act from their dashboard only on an email-addressed
  # invitation and only after proving control of that exact verified address.
  def self.accept_received!(invitation:, user:)
    process_received!(invitation: invitation, user: user, action: :accept)
  end

  def self.decline_received!(invitation:, user:)
    process_received!(invitation: invitation, user: user, action: :decline)
  end

  def self.process_received!(invitation:, user:, action:)
    outcome = nil
    ClaimInvitation.transaction do
      invitation.claimable.with_lock do
        invitation.with_lock do
          user.with_lock do
            unless invitation.status == "active" && invitation.expires_at > Time.current &&
                invitation.invitee_email.present? && invitation.verified_email_match?(user)
              invitation.update!(status: "expired") if invitation.status == "active" && invitation.expires_at <= Time.current
              next
            end

            if action == :decline
              invitation.update!(status: "declined", declined_at: Time.current)
              outcome = { invitation: invitation, outcome: :declined }
              next
            end

            account = user.account || Account.create!(user: user)
            subject = ClaimSubject.for(invitation.claimable)
            raise NotRedeemable unless subject.eligible? && subject.still_unclaimed?

            outcome = auto_link!(invitation: invitation, subject: subject, account: account, user: user)
          end
        end
      end
    end
    raise InvitationError, VERIFICATION_MESSAGE unless user.email_verified?
    raise InvitationError, INVALID_MESSAGE unless outcome

    outcome
  rescue NotRedeemable, ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, ClaimSubject::Ineligible
    raise InvitationError, INVALID_MESSAGE
  end
  private_class_method :process_received!

  # Records delivery telemetry for support/audit. It does not control whether a
  # verified exact-email recipient may link the subject.
  def self.mark_emailed!(invitation:)
    invitation.update!(emailed_at: Time.current)
    invitation
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest

  def self.auto_link!(invitation:, subject:, account:, user:)
    subject.effect!(claimant_account: account, actor: user)
    invitation.update!(status: "used", used_by: user, used_at: Time.current)
    { invitation: invitation, outcome: :linked, account: account }
  end
  private_class_method :auto_link!

end
