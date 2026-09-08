class MediaAsset < ApplicationRecord
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :drill
  belongs_to :skill, optional: true

  validates :title, presence: true
  validates :video_url, presence: true
  validates :asset_type, inclusion: { in: %w[example_demo actual_training_clip] }
end
