# VideoTagging — join model for Video <-> VideoTag.
#
# A video cannot be tagged with the same tag more than once.
class VideoTagging < ApplicationRecord
  belongs_to :video
  belongs_to :video_tag

  validates :video_id, uniqueness: { scope: :video_tag_id }
end
