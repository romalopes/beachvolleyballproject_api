# Configurable email-verification workflow.
#
# This service object owns everything about verification *except* the small state
# predicates living on the User model (email_verified?, etc.). Keeping the
# workflow here — token creation, delivery, validation, resend throttling —
# keeps the User model's authentication logic separate from verification logic.
#
# All gating uses EmailVerification.require? (the single config accessor) so the
# feature can be toggled off entirely without touching this flow.
class EmailVerificationService
  # Resend cooldown: don't allow a new verification email to be generated more
  # than this often for the same address (rate-limit protection, §8).
  RESEND_COOLDOWN = 1.minute

  # Generate a fresh verification token, invalidate any prior token, and deliver
  # the verification email. The raw token is returned (only the caller that
  # emails it ever sees it raw) but is never persisted or logged.
  def self.send_verification(user)
    raw_token = user.generate_email_verification_token!
    EmailVerificationsMailer.verification(user, raw_token).deliver_now
    raw_token
  end

  # Find the user by the *raw* token from the URL, consume the token (which
  # verifies the address and clears the token), and return the user. Returns nil
  # for an invalid or expired token — the caller renders a generic error so no
  # user-existence is leaked.
  def self.verify(raw_token)
    return nil if raw_token.blank?

    digest = digest_token(raw_token)
    user = User.find_by(email_verification_token_digest: digest)
    return nil unless user

    user.consume_email_verification_token(raw_token)
  end

  # Resend a verification email for the given address. The backend always returns
  # a uniform response so the client never learns whether the address exists,
  # is already verified, or verification is disabled. The only branching is
  # internal (cooldown enforcement).
  def self.resend(email_address)
    return unless EmailVerification.require?

    user = User.find_by(email_address: email_address)
    return unless user&.email_verification_pending?

    send_verification(user) unless within_cooldown?(user)
  end

  # The same digest computation the User model stores. Kept here so a single
  # raw token can be hashed for lookup without round-tripping through the DB.
  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  # True if a resend would violate the cooldown window. `nil` sent_at means no
  # prior resend, so it is allowed.
  def self.within_cooldown?(user)
    sent_at = user.email_verification_sent_at
    sent_at.present? && sent_at > RESEND_COOLDOWN.ago
  end
  private_class_method :digest_token, :within_cooldown?
end