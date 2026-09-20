# VideoTag — reusable tag for videos.
#
# Tag names are normalized (trim + downcase) so that "Reception", "reception"
# and " RECEPTION " all resolve to the same record.
class VideoTag < ApplicationRecord
  has_many :video_taggings, dependent: :destroy
  has_many :videos, through: :video_taggings

  validates :name, presence: true,
                   uniqueness: { case_sensitive: false,
                                 conditions: -> { where.not(name: nil) } }
  validates :position, numericality: { greater_than_or_equal_to: 0 }, allow_nil: false

  before_validation :normalize_name
  # Positions are app-managed (drag-and-drop in the settings page): a new tag is
  # appended after the last one rather than trusting a caller-supplied number.
  before_validation :assign_next_position, on: :create

  scope :ordered, -> { order(position: :asc, name: :asc) }

  def display_name
    name.titleize
  end

  # Usage count for list views. Prefers a `video_count` value produced by a
  # GROUP BY aggregate (see Api::V1::VideoTagsController#index) and falls back
  # to the association, which is cheap when `video_taggings` is preloaded so
  # unused tags correctly report 0 without an N+1.
  def video_count
    value = attributes["video_count"]
    value.nil? ? video_taggings.size : value.to_i
  end

  private

  def normalize_name
    return if name.blank?
    self.name = name.strip.downcase
  end

  def assign_next_position
    return if position.present? && position > 0
    self.position = (self.class.maximum(:position) || -1) + 1
  end
end
