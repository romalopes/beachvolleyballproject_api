# What a training works on. A focus is either a reference to an existing
# Skill (never created from the training workflow) or custom text. The
# optional `description` is training-specific — the same Skill may be worked
# on differently from session to session, so the global Skill is never
# modified.
class TrainingFocus < ApplicationRecord
  belongs_to :training_session
  belongs_to :skill, optional: true

  # Blank custom text must become NULL, otherwise a skill-based focus would
  # carry an empty string and violate the skill-xor-custom check constraint.
  normalizes :custom_focus, with: ->(value) { value.strip.presence }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       allow_nil: true
  validate :skill_must_exist
  # Skill-based focuses are unique within a training (the database enforces the
  # same rule through a unique index over [training_session_id, skill_id]).
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

  # A client-supplied skill id is never trusted; it must reference a real
  # Skill (which the training workflow itself never creates).
  def skill_must_exist
    return if skill_id.blank?
    return if Skill.exists?(skill_id)

    errors.add(:skill, "must exist")
  end

  # A focus must be exactly one of: an existing Skill, or custom text.
  def skill_or_custom_focus
    if skill_id.present? && custom_focus.present?
      errors.add(:base, "A training focus cannot reference a skill and custom text at the same time")
    elsif skill_id.blank? && custom_focus.blank?
      errors.add(:base, "A training focus must reference a skill or provide custom focus text")
    end
  end
end
