# One-time Account-claim invitation for a known Person without an Account.
class PersonAccountInvitationsMailer < ApplicationMailer
  def invitation(invitation, raw_token)
    @person = invitation.person
    @token = raw_token
    @expires_in = PersonAccountInvitation::DEFAULT_EXPIRATION
    @claim_url = "#{EmailVerification.frontend_url}/identity#account_claim_token=#{CGI.escape(raw_token)}"

    mail(to: invitation.invitee_email, subject: "Claim your Beach Volleyball Project account")
  end
end
