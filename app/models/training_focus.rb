# What a training works on. A focus is either a reference to an existing
# Skill (never created from the training workflow) or custom text. The
# optional `description` is training-specific — the same Skill may be worked
# on differently from session to session, so the global Skill is never
# modified.
class TrainingFocus < ApplicationRecord
  belongs_to :training_session
  belongs_to :skill, optional: true

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       allow_nil: true
  # Skill-based focuses are unique within a training; custom focuses are not
  # constrained (the database enforces the same rule via a partial-unique
  # index over [training_session_id, skill_id]).
  validates :skill_id, uniqueness: { scope: :training_session_id }, allow_nil: true
  validate :skill_or_custom_focus

  scope :ordered, -> { order(:position, :id) }

  def skill_based?
    skill_id.present?
  end

  def custom?
    custom_focus.present?
  end

  # Human-readable label used by the UI and the drill-recommendation panel.
  def label
    skill&.title.presence || custom_focus
  end

  private

  # A focus must be exactly one of: an existing Skill, or custom text.
  def skill_or_custom_focus
    if skill_id.present? && custom_focus.present?
      errors.add(:base, "A training focus cannot reference a skill and custom text at the same time")
    elsif skill_id.blank? && custom_focus.blank?
      errors.add(:base, "A training focus must reference a skill or provide custom focus text")
    end
  end
end
