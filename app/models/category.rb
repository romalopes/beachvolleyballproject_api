class Category < ApplicationRecord
  has_many :skills, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
