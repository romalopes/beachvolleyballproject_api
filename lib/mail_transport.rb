# frozen_string_literal: true

# Chooses one Action Mailer transport at boot. An explicit choice falls back
# safely when its required configuration is absent; automatic selection prefers
# HTTPS providers before SMTP and finally local file delivery.
class MailTransport
  SUPPORTED = %w[brevo resend smtp file].freeze

  def self.resolve(env = ENV, logger: nil) = new(env, logger: logger).resolve

  def initialize(env, logger: nil)
    @env = env
    @logger = logger
  end

  def resolve
    fallback = automatic
    requested = @env["MAIL_TRANSPORT"].to_s.strip.downcase
    return warn_multiple_keys(fallback) || fallback if requested.blank? || requested == "auto"
    return warn_and_fallback("Unknown MAIL_TRANSPORT=#{requested.inspect}", fallback) unless SUPPORTED.include?(requested)
    return warn_and_fallback("MAIL_TRANSPORT=brevo requires BREVO_API_KEY", fallback) if requested == "brevo" && !present?("BREVO_API_KEY")
    return warn_and_fallback("MAIL_TRANSPORT=resend requires RESEND_API_KEY", fallback) if requested == "resend" && !present?("RESEND_API_KEY")
    return warn_and_fallback("MAIL_TRANSPORT=smtp requires SMTP_ADDRESS", fallback) if requested == "smtp" && !present?("SMTP_ADDRESS")

    requested
  end

  private

  def automatic
    return "brevo" if present?("BREVO_API_KEY")
    return "resend" if present?("RESEND_API_KEY")
    return "smtp" if present?("SMTP_ADDRESS")

    "file"
  end

  def present?(key) = @env[key].to_s.strip.present?

  def warn_multiple_keys(selected)
    keys = %w[BREVO_API_KEY RESEND_API_KEY].select { |key| present?(key) }
    @logger&.warn("[email_delivery] #{keys.join(' and ')} are both set; using #{selected}. Set MAIL_TRANSPORT explicitly.") if keys.size > 1
    nil
  end

  def warn_and_fallback(reason, fallback)
    @logger&.warn("[email_delivery] #{reason}; using #{fallback} instead.")
    fallback
  end
end
