class AssessmentSessionParticipant < ApplicationRecord
  INCLUSIONS = %w[included excluded].freeze

  belongs_to :assessment_session, inverse_of: :participants
  belongs_to :player_profile

  validates :inclusion, inclusion: { in: INCLUSIONS }
  validates :player_profile_id, uniqueness: { scope: :assessment_session_id }

  scope :included, -> { where(inclusion: "included") }
  scope :excluded, -> { where(inclusion: "excluded") }

  def included?
    inclusion == "included"
  end

  def excluded?
    inclusion == "excluded"
  end
end
