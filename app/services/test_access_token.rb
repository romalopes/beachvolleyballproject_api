# Signed, expiring credentials for the private test-access gate.
#
# The application is in a private testing phase: only people who know the
# configured password (TEST_ACCESS_PASSWORD environment variable) may use it.
# The password itself lives server-side only; the browser receives a signed
# token (Rails message_verifier) that carries an expiry — it is not the
# password, and it cannot be forged or replayed after it expires.
#
# This is deliberately separate from the User/Session authentication system
# (Authentication concern, cookie + bearer sessions) so it can be removed
# later without touching real user accounts.
class TestAccessToken
  PURPOSE = :test_access

  # Abbreviation => ActiveSupport duration method name.
  UNITS = {
    "second" => :seconds, "sec" => :seconds, "s" => :seconds,
    "minute" => :minutes, "min" => :minutes,
    "hour" => :hours, "hr" => :hours,
    "day" => :days, "week" => :weeks
  }.freeze

  class << self
    # The configured password. Blank means the gate is disabled (development
    # and CI are unaffected when the variable is not set).
    def password
      ENV["TEST_ACCESS_PASSWORD"].presence
    end

    def enabled?
      password.present?
    end

    # Token lifetime. Defaults to 7 days; configurable via
    # TEST_ACCESS_TOKEN_EXPIRATION as "7.days", "12.hours", "3600" (seconds)
    # or ISO-8601 ("P7D").
    def expiration
      parse_duration(ENV["TEST_ACCESS_TOKEN_EXPIRATION"]) || 7.days
    end

    # Generates a signed token carrying the issue time and an expiry.
    def generate
      Rails.application.message_verifier(PURPOSE).generate(
        { v: 1, issued_at: Time.current.utc.iso8601 },
        expires_at: expiration.from_now,
        purpose: PURPOSE
      )
    end

    # Returns the payload hash for a valid, unexpired token; nil otherwise
    # (forged, tampered, wrong purpose or expired).
    def verify(token)
      return nil if token.blank?

      payload = Rails.application.message_verifier(PURPOSE).verified(
        token.to_s, purpose: PURPOSE
      )
      payload.is_a?(Hash) ? payload : nil
    end

    def valid?(token)
      verify(token).present?
    end

    # Constant-time password comparison (compares SHA-256 digests so even the
    # length of the candidate is not leaked).
    def matches?(candidate)
      return false unless enabled?
      return false if candidate.blank?

      ActiveSupport::SecurityUtils.secure_compare(
        digest(candidate.to_s), digest(password)
      )
    end

    private

    def digest(value)
      OpenSSL::Digest::SHA256.digest(value)
    end

    def parse_duration(raw)
      s = raw.to_s.strip
      return nil if s.blank?

      # Accepts Rails syntax ("7.days", "12.hours" — with or without the dot),
      # plain seconds ("3600") and ISO-8601 ("P7D").
      if (m = s.match(/\A(\d+)\.?\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?)\z/i))
        unit = m[2].downcase.sub(/s\z/, "")
        return m[1].to_i.public_send(UNITS.fetch(unit, :days))
      end
      return m[1].to_i.seconds if (m = s.match(/\A(\d+)\z/))

      ActiveSupport::Duration.parse(s) # ISO-8601, e.g. "P7D"
    rescue ArgumentError, TypeError
      nil
    end
  end
end
