class Account < ApplicationRecord
  belongs_to :user
  has_one :account_address, dependent: :destroy

  accepts_nested_attributes_for :account_address, reject_if: :all_blank

  validates :first_name, length: { maximum: 50 }, allow_nil: true
  validates :last_name, length: { maximum: 50 }, allow_nil: true
  validates :phone, length: { maximum: 30 }, allow_nil: true
  validate :date_of_birth_cannot_be_in_the_future

  private

  def date_of_birth_cannot_be_in_the_future
    return if date_of_birth.blank?
    errors.add(:date_of_birth, "cannot be in the future") if date_of_birth > Date.current
  end
end