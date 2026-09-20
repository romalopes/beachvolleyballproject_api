class MakeDrillTrainingAttributesOptional < ActiveRecord::Migration[7.1]
  def up
    change_column_null :drills, :training_stage, true
    change_column_null :drills, :difficulty_level, true
    change_column_null :drills, :min_players, true
    change_column_null :drills, :max_players, true
    change_column_null :drills, :ideal_num_players, true

    change_column_default :drills, :training_stage, nil
    change_column_default :drills, :difficulty_level, nil
    change_column_default :drills, :min_players, nil
    change_column_default :drills, :max_players, nil
    change_column_default :drills, :ideal_num_players, nil

    # Rebuild the DB guards so they tolerate NULL (optional attributes) while
    # still enforcing the same rules whenever values are present.
    remove_check_constraint :drills, name: "drills_training_stage_check"
    add_check_constraint :drills,
      "training_stage IS NULL OR training_stage::text = ANY (ARRAY['warmup'::character varying, 'beginning'::character varying, 'middle'::character varying, 'end'::character varying]::text[])",
      name: "drills_training_stage_check"

    remove_check_constraint :drills, name: "drills_difficulty_level_check"
    add_check_constraint :drills,
      "difficulty_level IS NULL OR difficulty_level::text = ANY (ARRAY['beginner'::character varying, 'intermediate'::character varying, 'advanced'::character varying]::text[])",
      name: "drills_difficulty_level_check"

    remove_check_constraint :drills, name: "drills_player_range_check"
    add_check_constraint :drills,
      "min_players IS NULL OR max_players IS NULL OR min_players <= max_players",
      name: "drills_player_range_check"

    remove_check_constraint :drills, name: "drills_ideal_players_check"
    add_check_constraint :drills,
      "ideal_num_players IS NULL OR min_players IS NULL OR max_players IS NULL OR (ideal_num_players >= min_players AND ideal_num_players <= max_players)",
      name: "drills_ideal_players_check"
  end

  def down
    # Reintroduce defaults and NOT NULL, backfilling blanks with the old
    # defaults so the NOT NULL constraints can be added safely.
    execute <<~SQL
      UPDATE drills SET training_stage = 'beginning' WHERE training_stage IS NULL;
      UPDATE drills SET difficulty_level = 'intermediate' WHERE difficulty_level IS NULL;
      UPDATE drills SET min_players = 2 WHERE min_players IS NULL;
      UPDATE drills SET max_players = 8 WHERE max_players IS NULL;
      UPDATE drills SET ideal_num_players = 4 WHERE ideal_num_players IS NULL;
    SQL

    change_column_default :drills, :training_stage, "beginning"
    change_column_default :drills, :difficulty_level, "intermediate"
    change_column_default :drills, :min_players, 2
    change_column_default :drills, :max_players, 8
    change_column_default :drills, :ideal_num_players, 4

    change_column_null :drills, :training_stage, false
    change_column_null :drills, :difficulty_level, false
    change_column_null :drills, :min_players, false
    change_column_null :drills, :max_players, false
    change_column_null :drills, :ideal_num_players, false

    remove_check_constraint :drills, name: "drills_training_stage_check"
    add_check_constraint :drills,
      "training_stage::text = ANY (ARRAY['warmup'::character varying, 'beginning'::character varying, 'middle'::character varying, 'end'::character varying]::text[])",
      name: "drills_training_stage_check"

    remove_check_constraint :drills, name: "drills_difficulty_level_check"
    add_check_constraint :drills,
      "difficulty_level::text = ANY (ARRAY['beginner'::character varying, 'intermediate'::character varying, 'advanced'::character varying]::text[])",
      name: "drills_difficulty_level_check"

    remove_check_constraint :drills, name: "drills_player_range_check"
    add_check_constraint :drills, "min_players <= max_players", name: "drills_player_range_check"

    remove_check_constraint :drills, name: "drills_ideal_players_check"
    add_check_constraint :drills,
      "ideal_num_players >= min_players AND ideal_num_players <= max_players",
      name: "drills_ideal_players_check"
  end
end
