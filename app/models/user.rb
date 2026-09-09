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

  def admin?
    has_role?(:admin)
  end
end
