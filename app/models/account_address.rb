class AccountAddress < ApplicationRecord
  belongs_to :account

  validates :street_address, length: { maximum: 255 }, allow_nil: true
  validates :city, :state, :postal_code, :country, length: { maximum: 100 }, allow_nil: true
end