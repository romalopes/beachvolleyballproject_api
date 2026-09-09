class Drill < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :drill_skills, dependent: :destroy
  has_many :skills, through: :drill_skills
  has_many :media_assets, dependent: :destroy
  has_many :training_sessions, dependent: :destroy

  validates :title, presence: true

  TRAINING_STAGES = %w[warmup beginning middle end].freeze
  DIFFICULTY_LEVELS = %w[beginner intermediate advanced].freeze

  validates :training_stage, presence: true, inclusion: { in: TRAINING_STAGES }
  validates :difficulty_level, presence: true, inclusion: { in: DIFFICULTY_LEVELS }
  validates :min_players, :max_players, :ideal_num_players,
            presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validate :min_players_not_greater_than_max_players
  validate :ideal_num_players_within_range

  def training_stage_label
    training_stage == "warmup" ? "Warm-up" : training_stage.to_s.capitalize
  end

  def player_range_label
    return nil if min_players.nil? || max_players.nil?
    min_players == max_players ? "#{min_players} players" : "#{min_players}–#{max_players} players"
  end

  def ideal_label
    ideal_num_players.nil? ? nil : "Ideal: #{ideal_num_players}"
  end

  private

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
