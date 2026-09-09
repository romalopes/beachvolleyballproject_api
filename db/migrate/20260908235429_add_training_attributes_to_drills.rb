class AddTrainingAttributesToDrills < ActiveRecord::Migration[8.1]
  STAGES = %w[warmup beginning middle end].freeze
  DIFFICULTIES = %w[beginner intermediate advanced].freeze

  def up
    rename_column :drills, :player_count, :ideal_num_players
    add_column :drills, :training_stage, :string
    add_column :drills, :min_players, :integer
    add_column :drills, :max_players, :integer

    execute(<<~SQL.squish)
      UPDATE drills
      SET ideal_num_players = 4, min_players = 2, max_players = 8
      WHERE ideal_num_players IS NULL OR ideal_num_players < 1
    SQL
    execute(<<~SQL.squish)
      UPDATE drills
      SET training_stage = 'beginning'
      WHERE training_stage IS NULL
        OR training_stage NOT IN ('warmup', 'beginning', 'middle', 'end')
    SQL
    execute(<<~SQL.squish)
      UPDATE drills
      SET difficulty_level = 'intermediate'
      WHERE difficulty_level IS NULL
        OR difficulty_level NOT IN ('beginner', 'intermediate', 'advanced')
    SQL
    execute(<<~SQL.squish)
      UPDATE drills
      SET min_players = CASE
          WHEN ideal_num_players = 1 THEN 1
          WHEN ideal_num_players = 2 THEN 2
          WHEN ideal_num_players = 3 THEN 2
          ELSE ideal_num_players - 1
        END,
        max_players = CASE
          WHEN ideal_num_players = 1 THEN 1
          WHEN ideal_num_players = 2 THEN 2
          WHEN ideal_num_players = 3 THEN 4
          ELSE ideal_num_players + 1
        END
      WHERE min_players IS NULL OR max_players IS NULL
    SQL

    change_column_default :drills, :training_stage, from: nil, to: "beginning"
    change_column_default :drills, :difficulty_level, from: nil, to: "intermediate"
    change_column_default :drills, :min_players, from: nil, to: 2
    change_column_default :drills, :max_players, from: nil, to: 8
    change_column_default :drills, :ideal_num_players, from: nil, to: 4
    change_column_null :drills, :training_stage, false
    change_column_null :drills, :difficulty_level, false
    change_column_null :drills, :min_players, false
    change_column_null :drills, :max_players, false
    change_column_null :drills, :ideal_num_players, false
    add_check_constraint :drills, "training_stage IN ('warmup', 'beginning', 'middle', 'end')", name: "drills_training_stage_check"
    add_check_constraint :drills, "difficulty_level IN ('beginner', 'intermediate', 'advanced')", name: "drills_difficulty_level_check"
    add_check_constraint :drills, "min_players <= max_players", name: "drills_player_range_check"
    add_check_constraint :drills, "ideal_num_players BETWEEN min_players AND max_players", name: "drills_ideal_players_check"
    add_index :drills, :training_stage
  end

  def down
    remove_index :drills, :training_stage
    remove_check_constraint :drills, name: "drills_ideal_players_check"
    remove_check_constraint :drills, name: "drills_player_range_check"
    remove_check_constraint :drills, name: "drills_difficulty_level_check"
    remove_check_constraint :drills, name: "drills_training_stage_check"
    change_column_null :drills, :ideal_num_players, true
    change_column_null :drills, :max_players, true
    change_column_null :drills, :min_players, true
    change_column_null :drills, :difficulty_level, true
    change_column_null :drills, :training_stage, true
    change_column_default :drills, :ideal_num_players, nil
    change_column_default :drills, :max_players, nil
    change_column_default :drills, :min_players, nil
    change_column_default :drills, :difficulty_level, nil
    change_column_default :drills, :training_stage, nil
    remove_column :drills, :max_players
    remove_column :drills, :min_players
    remove_column :drills, :training_stage
    rename_column :drills, :ideal_num_players, :player_count
  end
end