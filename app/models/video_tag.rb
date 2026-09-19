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

  before_validation :normalize_name

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
end
