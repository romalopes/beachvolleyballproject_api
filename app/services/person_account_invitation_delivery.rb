# Email delivery is optional. The invitation link remains available to copy if
# the mail gate is disabled or the SMTP provider fails.
class PersonAccountInvitationDelivery
  def self.deliver(invitation:, raw_token:)
    return false unless PlayerClaimInvitationEmail.enabled?

    PersonAccountInvitationsMailer.invitation(invitation, raw_token).deliver_now
    true
  rescue StandardError => e
    Rails.logger.error("[person_account_invitation] delivery failed: #{e.class}: #{e.message}")
    false
  end
end
