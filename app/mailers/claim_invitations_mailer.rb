# Claim invitation email.
#
# Sent when a coach restricts an invitation to one address. Modelled on
# EmailVerificationsMailer: the raw token is handed in only by the delivery
# service that just generated it, appears solely in the link, and is never
# persisted (only the digest is) or logged.
#
# Delivery is always optional. The invitation exists and its link works the
# moment it is created, whether or not this mail ever leaves the outbox.
class ClaimInvitationsMailer < ApplicationMailer
  # @param invitation [ClaimInvitation] the persisted invitation (metadata only)
  # @param raw_token [String] the one-time token to embed in the link
  def invitation(invitation, raw_token)
    @invitation = invitation
    @token = raw_token
    @subject = ClaimSubject.for(invitation.claimable)
    @inviter_name = invitation.invited_by&.person&.full_name || invitation.invited_by&.name
    @expires_in = ClaimInvitation::DEFAULT_EXPIRATION
    @claim_url = claim_url(raw_token)

    mail(
      to: invitation.invitee_email,
      subject: "You have been invited to claim your #{@subject.label}"
    )
  end

  private

  # The token lives in the URL *fragment*: browsers do not send fragments in
  # HTTP requests, so it never reaches a server access log or a Referer header
  # (the same reasoning as Phase 13).
  def claim_url(raw_token)
    base = EmailVerification.frontend_url
    "#{base}/identity#claim_token=#{CGI.escape(raw_token)}"
  end
end
