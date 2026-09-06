class Skill < ApplicationRecord
  belongs_to :category
  has_many :drill_skills, dependent: :destroy
  has_many :drills, through: :drill_skills
  has_many :media_assets, dependent: :nullify

  validates :title, presence: true
end
