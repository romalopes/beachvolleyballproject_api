# VideoCategory — a first-class category for grouping videos.
#
# Mirrors the existing Category/Skill pattern (name + slug + ordering).
class VideoCategory < ApplicationRecord
  include Sluggable
  source_column :name

  has_many :videos, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :position, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false

  # Positions are app-managed (drag-and-drop in the settings page): a new
  # category is appended after the last one instead of trusting a typed number.
  before_validation :assign_next_position, on: :create

  scope :ordered, -> { order(Arel.sql("position ASC, name ASC")) }

  # Usage count for list views. Prefers a `video_count` column produced by a
  # GROUP BY aggregate (`select("video_categories.*, COUNT(*) AS video_count")`)
  # and falls back to the association, which is cheap when `videos` is
  # preloaded (see Api::V1::VideoCategoriesController#index).
  def video_count
    value = attributes["video_count"]
    value.nil? ? videos.size : value.to_i
  end

  private

  def assign_next_position
    return if position.present? && position > 0
    self.position = (self.class.maximum(:position) || -1) + 1
  end
end
