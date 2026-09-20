# Email verification mailer.
#
# Sent when REQUIRE_EMAIL_VERIFICATION=true and a user (or an admin on their
# behalf via resend) triggers a verification email. The raw token is passed in
# only by the controller/service that generates it for delivery; the *digest*
# is what lives on the User. The raw token appears solely in the email link,
# never persisted or logged.
class EmailVerificationsMailer < ApplicationMailer
  # @param user [User] the user being verified
  # @param raw_token [String] the one-time token to embed in the link
  def verification(user, raw_token)
    @user        = user
    @token       = raw_token
    @expires_in  = EmailVerification.expiration
    @verify_url  = verify_email_url(raw_token)

    mail(to: user.email_address, subject: "Verify your email address for Beach Volleyball Project")
  end

  private

  # Builds the frontend URL that the user clicks to verify. The token is the only
  # sensitive value in the URL (§14): no user id, no email, no token type.
  def verify_email_url(raw_token)
    base = EmailVerification.frontend_url
    "#{base}/verify-email?token=#{raw_token}"
  end
end