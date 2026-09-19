# VideoReference — the contextual use of a Video by a Drill or Skill: the
# relevance window (start/end seconds), per-use title/description and display
# order. The Video itself stays shared and untouched by reference deletion.
#
# The polymorphic `referenced` keeps the door open for future referencable
# types (TrainingSession, Tournament, …) without new join tables.
class VideoReference < ApplicationRecord
  belongs_to :video
  belongs_to :referenced, polymorphic: true

  validates :start_seconds, :end_seconds,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :end_after_start, if: -> { start_seconds && end_seconds }
  validate :within_video_duration,
           if: -> { end_seconds && video&.duration_seconds.present? }

  before_validation :assign_next_position

  # Playback fields normalized for the API: the reference knows its own window,
  # the Video's provider decides how (and whether) it can be played.
  delegate :can_embed?, :external_url, :provider_label, to: :video

  def embed_url
    video.embed_url(start_seconds, end_seconds)
  end

  # API field name without the Ruby predicate suffix (rendered as "can_embed").
  alias_method :can_embed, :can_embed?

  private

  # References are listed in `position` order per referenced object; a row
  # created without one appends to the end.
  def assign_next_position
    return if position.present? || referenced.nil?

    last = referenced.video_references.maximum(:position)
    self.position = last.nil? ? 0 : last + 1
  end

  def end_after_start
    return if end_seconds > start_seconds

    errors.add(:end_seconds, "must be greater than start_seconds")
  end

  # Only enforced when the Video's duration is actually known; external videos
  # without duration data are never rejected for that reason alone.
  def within_video_duration
    return if end_seconds <= video.duration_seconds

    errors.add(:end_seconds, "cannot be after the video duration")
  end
end
