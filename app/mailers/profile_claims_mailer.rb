class ProfileClaimsMailer < ApplicationMailer
  def decision(claim)
    @claim = claim
    @profile = claim.subject
    @account = claim.claimant_account
    @decision = claim.status
    @profile_name = @profile&.full_name || @profile&.display_name || "your profile"

    mail(
      to: @account.user.email_address,
      subject: "Your profile claim was #{@decision}"
    )
  end
end
