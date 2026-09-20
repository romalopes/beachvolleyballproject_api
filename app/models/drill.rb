# Explicitly require the validator: app/validators was added after the running
# server booted, and Zeitwerk only picks up new autoload roots at boot. The
# eager require keeps this robust across stale dev-server processes.
require Rails.root.join("app/validators/drill_definition_validator")

class Drill < ApplicationRecord
  include Sluggable
  source_column :title

  belongs_to :created_by, class_name: "User", optional: true
  has_many :drill_skills, dependent: :destroy
  has_many :skills, through: :drill_skills
  has_many :video_references, as: :referenced, dependent: :destroy
  has_many :videos, through: :video_references
  # A drill is referenced by training sessions through ordered join rows; the
  # join row is destroyed with the drill, never the training session itself.
  has_many :training_session_drills, dependent: :destroy
  has_many :training_sessions, through: :training_session_drills

  validates :title, presence: true

  validate :definition_must_be_valid

  TRAINING_STAGES = %w[warmup beginning middle end].freeze
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced].freeze

  # These training attributes are optional: inclusion/numericality skip nil
  # values (allow_nil), while cross-field checks still apply whenever both
  # sides of the comparison are present.
  validates :training_stage, inclusion: { in: TRAINING_STAGES, allow_nil: true }
  validates :difficulty_level, inclusion: { in: DIFFICULTY_LEVELS, allow_nil: true }
  validates :min_players, :max_players, :ideal_num_players,
            numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validate :min_players_not_greater_than_max_players
  validate :ideal_num_players_within_range

  def training_stage_label
    return nil if training_stage.nil?
    training_stage == "warmup" ? "Warm-up" : training_stage.to_s.capitalize
  end

  def player_range_label
    return nil if min_players.nil? || max_players.nil?
    min_players == max_players ? "#{min_players} players" : "#{min_players}–#{max_players} players"
  end

  def ideal_label
    ideal_num_players.nil? ? nil : "Ideal: #{ideal_num_players}"
  end

  def to_param
    slug
  end

  private

  def definition_must_be_valid
    DrillDefinitionValidator.new(self).validate
  end

  def min_players_not_greater_than_max_players
    return if min_players.nil? || max_players.nil?
    errors.add(:min_players, "must be less than or equal to max players") if min_players > max_players
  end

  def ideal_num_players_within_range
    return if ideal_num_players.nil? || min_players.nil? || max_players.nil?
    unless ideal_num_players >= min_players && ideal_num_players <= max_players
      errors.add(:ideal_num_players, "must be between min and max players (inclusive)")
    end
  end
end
