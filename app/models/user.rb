class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_one :account, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email address" }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Role checks
  def has_role?(role_name)
    roles.exists?(name: role_name.to_s)
  end

  def add_role(role_name)
    role = Role.find_by(name: role_name.to_s)
    return false unless role

    user_roles.find_or_create_by!(role: role)
  end

  def remove_role(role_name)
    role = Role.find_by(name: role_name.to_s)
    return false unless role

    user_roles.where(role: role).destroy_all
    true
  end

  # Role predicates. `guest?` is always false on a persisted user; the guest
  # role is an authorization state for unauthenticated visitors.
  def guest?
    false
  end

  def player?
    has_role?(:player)
  end

  def coach?
    has_role?(:coach)
  end

  def curator?
    has_role?(:curator)
  end

  def admin?
    has_role?(:admin)
  end

    # Users who may create/manage shared content (skills, drills, media and
  # training sessions). Visibility is separate from management: everyone can
  # browse the shared schedule, but only these roles may mutate it.
  def content_manager?
    coach? || curator? || admin?
  end

  # --- Email verification state ----------------------------------------------
  # These are pure state predicates. The workflow (token generation, delivery,
  # validation) lives in EmailVerificationService to keep the verification
  # logic separate from general authentication.

  # True once the user has clicked a valid verification link.
  def email_verified?
    email_verified_at.present?
  end

  # True while verification is required by config and the user has not yet
  # confirmed their address. Such users may not authenticate even though
  # their account exists.
  def email_verification_pending?
    EmailVerification.require? && !email_verified?
  end

  # Generate (and persist) a fresh verification token for this user, return the
  # *raw* token so the caller (the mailer) can email it. The digest of the token
  # is what is stored — the raw value never lands in the database or logs.
  def generate_email_verification_token!
    raw_token = SecureRandom.urlsafe_base64(32)
    self.email_verification_token_digest = Digest::SHA256.hexdigest(raw_token)
    self.email_verification_sent_at = Time.current
    save!
    raw_token
  end

  # Consume a verification token: verify the user if the digest matches and the
  # token has not expired. Returns the user on success, nil otherwise. Clears
  # the token so it is single-use.
  def consume_email_verification_token(raw_token)
    return nil if email_verification_token_digest.blank?

    threshold = Time.current - EmailVerification.expiration
    return nil if email_verification_sent_at && email_verification_sent_at < threshold

    expected = Digest::SHA256.hexdigest(raw_token)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(expected, email_verification_token_digest)

    update!(
      email_verified_at: Time.current,
      email_verification_token_digest: nil,
      email_verification_sent_at: nil
    )
    self
  end
end
