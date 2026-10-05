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
# Returning true is what lets the caller stamp `emailed_at`, which is in turn
# what allows the invitation to auto-approve. A failure therefore downgrades the
# invitation to staff review — the safe direction.
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

# Superseded by ClaimInvitationDelivery (the unified workflow's only delivery
# path). This controller and its endpoints are retained for one release.
