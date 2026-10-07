# Optional email delivery for a claim invitation.
#
# Two rules, both deliberate:
#
#   * Nothing is sent unless the invitation names an address. An open bearer
#     link has no recipient, so the coach shares the link themselves.
#   * A delivery failure never fails the request. The invitation and its link
#     already exist and work; the coach can still copy the link, and being able
#     to invite somebody must not depend on the SMTP relay being up.
#
# Returning true lets the caller record `emailed_at` for delivery reporting. It
# does not affect authorization: only a verified exact email match can link an
# invitation subject automatically, whether delivery succeeded or the link was
# shared manually.
class ClaimInvitationDelivery
  def self.deliver(invitation:, raw_token:)
    return false unless invitation&.invitee_email.present?
    return false unless PlayerClaimInvitationEmail.enabled?

    ClaimInvitationsMailer.invitation(invitation, raw_token).deliver_now
    true
  rescue StandardError => e
    Rails.logger.error("[claim_invitation] delivery failed: #{e.class}: #{e.message}")
    false
  end
end

