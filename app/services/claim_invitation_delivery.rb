# Optional delivery of an address-restricted claim invitation.
#
# Two rules, both deliberate:
#
#   * Nothing is sent unless the invitation names an address. An open bearer
#     invitation has no recipient, so the coach shares the link themselves.
#   * A delivery failure never fails the request. The invitation and its link
#     already exist and work; the coach can still copy the link, and being able
#     to invite a player must not depend on the SMTP relay being up.
class PlayerClaimInvitationDelivery
  def self.deliver(invitation:, raw_token:, inviter_name: nil)
    return unless invitation&.invitee_email.present?
    return unless PlayerClaimInvitationEmail.enabled?

    PlayerClaimInvitationsMailer
      .invitation(invitation, raw_token, inviter_name || invitation.created_by_person&.full_name)
      .deliver_now
  rescue StandardError => e
    # Logged, not raised: see the class comment.
    Rails.logger.error("[claim_invitation] delivery failed: #{e.class}: #{e.message}")
    nil
  end
end
