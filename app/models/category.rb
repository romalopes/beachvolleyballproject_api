class Category < ApplicationRecord
  include Sluggable
  source_column :name

  has_many :skills, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  def to_param
    slug
  end
end
