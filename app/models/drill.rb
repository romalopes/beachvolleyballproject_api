class Drill < ApplicationRecord
  has_many :drill_skills, dependent: :destroy
  has_many :skills, through: :drill_skills
  has_many :media_assets, dependent: :destroy
  has_many :training_sessions, dependent: :destroy

  validates :title, presence: true
  validates :player_count, numericality: { greater_than: 0 }, allow_nil: true
end
