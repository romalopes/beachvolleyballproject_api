# A Drill selected for a Training Session.
#
# Only the order, the session-specific duration and session-specific notes
# live here. The Drill's description, skills, visual definition and steps are
# always read from the Drill record — never copied — so Drill versioning or
# edits stay consistent everywhere.
class TrainingSessionDrill < ApplicationRecord
  belongs_to :training_session
  belongs_to :drill

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       allow_nil: true
  validates :drill_id, uniqueness: { scope: :training_session_id }
  # Optional, but must be a positive whole number of minutes when supplied.
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 },
                               allow_nil: true

  scope :ordered, -> { order(:position, :id) }
end
