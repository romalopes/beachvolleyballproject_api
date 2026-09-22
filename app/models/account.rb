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
  belongs_to :person, optional: true, inverse_of: :account, autosave: true
  has_one :account_address, dependent: :destroy

  accepts_nested_attributes_for :account_address, reject_if: :all_blank

  # Contact fields live on Person; delegate for compatibility with the
  # previous Account-only attributes.
  delegate :first_name, :last_name, :phone, :date_of_birth, :full_name,
           to: :person, prefix: false, allow_nil: true

  # Every Account always has a Person: volleyball identity is mandatory,
  # authentication is what is optional.
  before_validation :ensure_person, on: :create

  validates :user_id, uniqueness: true
  validate :person_is_unique_across_accounts

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
      email: user&.email_address,
      creation_source: "signup",
      created_by: user
    )
    @transitional_first_name = @transitional_last_name = nil
    @transitional_phone = @transitional_date_of_birth = nil
    person
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

  private

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