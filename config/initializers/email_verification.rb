# Central configuration for the configurable email-verification feature.
#
# REQUIRE_EMAIL_VERIFICATION (default: false):
#   false -> registration and login behave exactly as today; no verification
#            email is sent and no verification is required.
#   true  -> newly registered users must verify their email before they can
#            authenticate and use the application.
#
# EMAIL_VERIFICATION_EXPIRATION_HOURS (default: 24):
#   How long a verification link remains valid after it is generated.
#
# This initializer is the *only* place that reads these ENV keys for auth
# gating purposes. Controllers, models and services must go through
# EmailVerification.require? / EmailVerification.expiration so the feature
# toggle is centralized and never scattered as ENV[...] checks across the
# codebase.
module EmailVerification
  module_function

  def require?
    ActiveModel::Type::Boolean.new.cast(ENV["REQUIRE_EMAIL_VERIFICATION"])
  end

  def expiration
    hours = (ENV["EMAIL_VERIFICATION_EXPIRATION_HOURS"].presence || 24).to_f
    hours.hours
  end

  # Base URL of the React SPA for verification links. Defaults to the local
  # dev server. Overridden per deploy with FRONTEND_URL.
  def frontend_url
    ENV["FRONTEND_URL"].presence || "http://localhost:5174"
  end

  # When true (the default when verification is required), newly registered
  # users automatically receive a verification email. Set to "false" to require
  # users to manually request a resend before receiving their verification email.
  def auto_send_on_signup?
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch("EMAIL_VERIFICATION_AUTO_SEND_ON_SIGNUP", "true")
    )
  end
end

Rails.logger.info("EmailVerification.require?=#{EmailVerification.require?}") if Rails.logger