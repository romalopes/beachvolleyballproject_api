# Issues, redeems and revokes claim invitations for any subject kind.
#
# The authorization rule is a matching verified email. Whether the application
# sent or the coach manually shared the link does not change ownership proof.
# An open profile invitation without an email recipient creates a pending claim.
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

    # A Person subject always carries its own address; a profile only when the
    # club supplies one, so a placeholder player stays an open bearer link.
    address = subject.default_email || invitee_email.presence
    raw_token = SecureRandom.urlsafe_base64(32)

    invitation = ClaimInvitation.transaction do
      claimable.with_lock do
        subject = ClaimSubject.for(claimable)
        raise InvitationError, subject.ineligibility_reason unless subject.eligible?

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

  # Returns what happened, so the caller can tell an immediate link from a
  # request awaiting review:
  #   { invitation:, outcome: :linked, person: }
  #   { invitation:, outcome: :pending_review, claim: }
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

              # Some existing Users predate Account provisioning. Create the
              # authentication-to-identity bridge in this same transaction so
              # a verified invitee never receives a second Person later.
              account = user.account || Account.create!(user: user)
              claimant_person = account.person
              raise NotRedeemable unless claimant_person&.status == "active"

              subject = ClaimSubject.for(invitation.claimable)
              # The record may have been archived, cleared of its required
              # display name, or linked since issuance. Reapply the exact
              # eligibility check while holding both subject and invitation
              # locks so stale links cannot revive an ineligible record.
              raise NotRedeemable unless subject.eligible? && subject.still_unclaimed?

              outcome = if invitation.verified_email_match?(user)
                          auto_link!(invitation: invitation, subject: subject,
                                     claimant_person: claimant_person, user: user)
              else
                          enqueue_for_review!(invitation: invitation, subject: subject,
                                              claimant_person: claimant_person, user: user)
              end
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

    # No usable invitation and no Person to redeem against: the caller must
    # verify their address before anything else can be attempted.
    raise InvitationError, VERIFICATION_MESSAGE if user.person.nil?

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

  def self.auto_link!(invitation:, subject:, claimant_person:, user:)
    subject.effect!(claimant_person: claimant_person, actor: user)
    invitation.update!(status: "used", used_by: user, used_at: Time.current)
    { invitation: invitation, outcome: :linked, person: invitation.claimable }
  end
  private_class_method :auto_link!

  # A link by itself does not prove identity. When there is no verified exact
  # email match, possession of the invite authorizes a request for staff review.
  def self.enqueue_for_review!(invitation:, subject:, claimant_person:, user:)
    account = user.account
    raise InvitationError, INVALID_MESSAGE unless account
    raise InvitationError, INVALID_MESSAGE if pending_claim_for?(invitation, account: account)

    claim = PlayerClaim.create!(
      claimable: invitation.claimable,
      person: claimant_person,
      initiated_by_person: invitation.invited_by.person || claimant_person,
      claimant_account: account,
      status: "pending"
    )
    invitation.update!(status: "used", used_by: user, used_at: Time.current)
    { invitation: invitation, outcome: :pending_review, claim: claim }
  end
  private_class_method :enqueue_for_review!

  def self.pending_claim_for?(invitation, account:)
    PlayerClaim.pending.where(claimable_type: invitation.claimable_type,
                              claimable_id: invitation.claimable_id,
                              claimant_account: account).exists?
  end
  private_class_method :pending_claim_for?
end
