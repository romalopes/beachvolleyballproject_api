# Issues, redeems and revokes claim invitations for any subject kind.
#
# The single most important rule here is the auto-approve gate. Redemption only
# links an identity immediately when the invitation was **emailed** to the
# address the recipient controls:
#
#   1. invitee_email is set, and
#   2. emailed_at is set (the club's mailer accepted the message), and
#   3. the signed-in user's address matches, and
#   4. that address is verified.
#
# Anything else — a link copied by hand, an invitation whose email never went
# out, an unverified account, a backfilled row with no emailed_at — becomes a
# *pending claim* for staff review instead. That is the fail-closed direction:
# a broken SMTP relay must never turn into a silent identity grant.
class ClaimInvitationService
  class InvitationError < StandardError; end

  # Internal signal: the invitation cannot be redeemed by this caller, and
  # nothing was written. Raised inside the transaction so the rollback leaves the
  # invitation usable, then translated into `InvitationError` outside it.
  class NotRedeemable < StandardError; end

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
              claimant_person = user.person
              raise NotRedeemable unless claimant_person&.status == "active"

              # An address-restricted invitation is refused for anyone else, with
              # the same generic message, so the endpoint never confirms that a
              # given address was invited.
              if invitation.invitee_email.present? &&
                 user.email_address.to_s.strip.downcase != invitation.invitee_email
                raise NotRedeemable
              end

              subject = ClaimSubject.for(invitation.claimable)
              raise NotRedeemable unless subject.still_unclaimed?

              outcome = if invitation.delivered_to?(user)
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

  # Records that the club actually sent the message. Without this the invitation
  # cannot auto-approve (see the gate in `redeem!`).
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

  # The emailed link did not prove anything on its own, so the claim waits for a
  # coach or administrator. Possession of an invite authorizes a *request*.
  def self.enqueue_for_review!(invitation:, subject:, claimant_person:, user:)
    raise InvitationError, INVALID_MESSAGE if pending_claim_for?(invitation)

    claim = PlayerClaim.create!(
      claimable: invitation.claimable,
      person: claimant_person,
      initiated_by_person: invitation.invited_by.person || claimant_person,
      status: "pending"
    )
    invitation.update!(status: "used", used_by: user, used_at: Time.current)
    { invitation: invitation, outcome: :pending_review, claim: claim }
  end
  private_class_method :enqueue_for_review!

  def self.pending_claim_for?(invitation)
    PlayerClaim.pending.where(claimable_type: invitation.claimable_type,
                              claimable_id: invitation.claimable_id).exists?
  end
  private_class_method :pending_claim_for?
end
