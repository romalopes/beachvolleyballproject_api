class Skill < ApplicationRecord
  include Sluggable
  source_column :title

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :category
  has_many :drill_skills, dependent: :destroy
  has_many :drills, through: :drill_skills
  has_many :media_assets, dependent: :nullify

  validates :title, presence: true

  def to_param
    slug
  end
end
