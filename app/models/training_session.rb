class TrainingSession < ApplicationRecord
  belongs_to :drill

  validates :scheduled_at, presence: true
end
