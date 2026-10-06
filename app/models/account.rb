# The bridge between authentication (User) and domain identity (Person).
#
# Contact/profile data (names, phone, date of birth) moved to Person so that a
# real-world individual can exist — with their full volleyball history —
# before they ever create an account. Account now carries the link:
#
#   User (authentication) 1—1 Account 1—1 Person ─┬─ 0..1 PlayerProfile
#                                                 └─ 0..1 CoachProfile
class Account < ApplicationRecord
  belongs_to :user
  belongs_to :person, inverse_of: :account, autosave: true
  has_one :account_address, dependent: :destroy
  has_one :contact_detail, inverse_of: :account, dependent: :restrict_with_error, autosave: true
  has_many :player_profiles, dependent: :restrict_with_error
  has_many :coach_profiles, dependent: :restrict_with_error

  accepts_nested_attributes_for :account_address, reject_if: :all_blank

  # ContactDetail is the account-owned read source. Fall back to Person while
  # constructing a new Account before its required ContactDetail exists.
  %i[first_name last_name email phone date_of_birth].each do |field|
    define_method(field) do
      detail = contact_detail
      detail ? detail.public_send(field) : person&.public_send(field)
    end
  end

  def full_name
    [ first_name, last_name ].compact.join(" ")
  end

  # Every Account always has a Person: volleyball identity is mandatory,
  # authentication is what is optional.
  before_validation :ensure_person, on: :create
  before_validation :ensure_contact_detail, on: :create
  validates :contact_detail, presence: true
  after_save :synchronize_contact_detail_from_person

  validates :user_id, uniqueness: true
  validate :person_is_unique_across_accounts

  # Authorization roles continue to live on User for compatibility, while
  # policies can treat Account as the application identity principal.
  def has_role?(name) = user&.has_role?(name) || false
  def admin? = has_role?(:admin)
  def curator? = has_role?(:curator)
  def coach? = has_role?(:coach)
  def player? = has_role?(:player)

  # Creates the Account's Person if it does not exist yet; safe to call
  # repeatedly. Values assigned through the transitional account-level
  # setters (below) are handed over to the new Person.
  def ensure_person
    return person if person

    first_name, last_name = split_fallback_name
    build_person(
      first_name: @transitional_first_name || first_name,
      last_name: @transitional_last_name || last_name,
      phone: @transitional_phone,
      date_of_birth: @transitional_date_of_birth,
      email: @transitional_email || user&.email_address,
      creation_source: "signup",
      created_by: user
    )
    @transitional_first_name = @transitional_last_name = nil
    @transitional_phone = @transitional_date_of_birth = nil
    @transitional_email = nil
    person
  end

  # ContactDetails is the account-owned copy of private contact information.
  # Person remains the compatibility source during the expand phase, so every
  # Account is created with a matching snapshot and existing Person edits keep
  # the two records aligned.
  def ensure_contact_detail
    return contact_detail if contact_detail
    return unless person

    build_contact_detail(
      first_name: person.first_name,
      last_name: person.last_name,
      email: person.email,
      phone: person.phone,
      date_of_birth: person.date_of_birth
    )
  end

  # Transitional setters: capture values until a Person exists to receive
  # them (delegating to a nil person would raise). Once the Person exists
  # the setters forward to it directly via the delegates above.
  def first_name=(value)
    capture_transitional(:first_name, value)
  end

  def last_name=(value)
    capture_transitional(:last_name, value)
  end

  def phone=(value)
    capture_transitional(:phone, value)
  end

  def date_of_birth=(value)
    capture_transitional(:date_of_birth, value)
  end

  def email=(value)
    capture_transitional(:email, value)
  end

  private

  def synchronize_contact_detail_from_person
    return unless person && contact_detail

    attributes = {
      first_name: person.first_name,
      last_name: person.last_name,
      email: person.email,
      phone: person.phone,
      date_of_birth: person.date_of_birth
    }
    return unless attributes.any? { |key, value| contact_detail.public_send(key) != value }

    attributes.each { |key, value| contact_detail.public_send(:"#{key}=", value) }
    contact_detail.save! if contact_detail.new_record?
    contact_detail.update_columns(attributes.merge(updated_at: Time.current)) if contact_detail.persisted?
  end

  # When no explicit name was given, derive one from the User's display name
  # so Person.first_name (required) is always populated on signup.
  def split_fallback_name
    name = user&.name.to_s.strip
    return [ nil, nil ] if name.empty?

    parts = name.split(/\s+/, 2)
    [ parts[0], parts[1] ]
  end

  def capture_transitional(attribute, value)
    if person
      person.public_send(:"#{attribute}=", value)
      contact_detail.public_send(:"#{attribute}=", value) if contact_detail
    else
      instance_variable_set("@transitional_#{attribute}", value)
    end
  end

  # DB constraint backs this up (unique index on accounts.person_id); this
  # validation gives a friendly error instead of RecordNotUnique.
  def person_is_unique_across_accounts
    return unless person_id

    conflict = Account.where(person_id: person_id).where.not(id: id).exists?
    errors.add(:person, "is already linked to another account") if conflict
  end
end
