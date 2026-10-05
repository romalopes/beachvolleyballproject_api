# Central configuration for claim-invitation email delivery.
#
# CLAIM_INVITATION_EMAIL_ENABLED (default: false):
#   false -> an address-restricted invitation is created and its link works, but
#            no mail is sent and the coach shares the link themselves.
#   true  -> the invitation email is delivered to the invited address.
#
# Defaulting to false keeps a development or misconfigured deployment from
# attempting SMTP against a real address it does not own. Turning it on is a
# deliberate deploy decision.
module PlayerClaimInvitationEmail
  module_function

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV["CLAIM_INVITATION_EMAIL_ENABLED"])
  end
end

Rails.logger&.info("PlayerClaimInvitationEmail.enabled?=#{PlayerClaimInvitationEmail.enabled?}")
