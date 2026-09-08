class TrainingSession < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :drill

  validates :scheduled_at, presence: true
end
