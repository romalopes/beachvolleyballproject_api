# Future media support for Training Sessions. Reuses the existing MediaAsset
# model (YouTube/Vimeo/uploaded video/external links); no training-specific
# media model is introduced. The UI for this is intentionally not part of the
# initial training phase.
class TrainingSessionMediaAsset < ApplicationRecord
  belongs_to :training_session
  belongs_to :media_asset

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       allow_nil: true
  validates :media_asset_id, uniqueness: { scope: :training_session_id }

  scope :ordered, -> { order(:position, :id) }
end
