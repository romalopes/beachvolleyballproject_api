# Application identity and owner of private contact details and volleyball
# profiles. Authentication credentials and role assignments remain on User.
class Account < ApplicationRecord
  # Staff may record an Account before its owner signs up. Claiming attaches
  # the login User later; the Account and ContactDetail remain the durable
  # volleyball identity throughout.
  belongs_to :user, optional: true
  has_one :account_address, dependent: :destroy
  has_one :contact_detail, inverse_of: :account, dependent: :destroy, autosave: true
  has_many :player_profiles, dependent: :restrict_with_error
  has_many :coach_profiles, dependent: :restrict_with_error
  has_many :organisation_memberships, dependent: :restrict_with_error
  has_many :group_memberships, dependent: :restrict_with_error
  has_many :organisations, through: :organisation_memberships
  has_many :groups, through: :group_memberships

  accepts_nested_attributes_for :account_address, reject_if: :all_blank

  %i[first_name last_name email phone date_of_birth].each do |field|
    define_method(field) { contact_detail&.public_send(field) }
    define_method(:"#{field}=") do |value|
      build_contact_detail unless contact_detail
      contact_detail.public_send(:"#{field}=", value)
    end
  end

  def full_name
    [ first_name, last_name ].compact.join(" ")
  end

  before_validation :ensure_contact_detail
  validates :contact_detail, presence: true
  validates :user_id, uniqueness: true

  def claimed? = user_id.present?

  def has_role?(name) = user&.has_role?(name) || false
  def admin? = has_role?(:admin)
  def curator? = has_role?(:curator)
  def coach? = has_role?(:coach)
  def player? = has_role?(:player)

  private

  def ensure_contact_detail
    return if contact_detail

    contact = build_contact_detail
    # Legacy programmatic account creation may not provide contact details.
    # Signup always does; this fallback keeps old records valid without adding a
    # second name field to User.
    contact.first_name = user&.email_address.to_s.split("@", 2).first.presence if contact.first_name.blank?
    contact.email = user.email_address if contact.email.blank? && user&.email_address.present?
  end
end
