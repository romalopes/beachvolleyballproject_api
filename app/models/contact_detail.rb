# Private personal and contact information for one authenticated Account.
# Contact email is independent from User.email_address, which is used to sign in.
class ContactDetail < ApplicationRecord
  belongs_to :account, inverse_of: :contact_detail

  validates :account_id, uniqueness: true
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name, length: { maximum: 50 }
  # Preserve legacy contact values as-is during backfill. Existing Person.email
  # did not enforce format, and this phase must not make old Accounts unsavable.
  validates :phone, length: { maximum: 30 }, allow_nil: true
  validate :date_of_birth_cannot_be_in_the_future

  private

  def date_of_birth_cannot_be_in_the_future
    return if date_of_birth.blank?

    errors.add(:date_of_birth, "cannot be in the future") if date_of_birth > Date.current
  end
end
