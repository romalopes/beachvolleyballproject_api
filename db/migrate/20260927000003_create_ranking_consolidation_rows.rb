# Phase 4 (Ranking Consolidation), plan §8: one frozen row per ranked player,
# storing every source session's score plus the merged average (D22).
#
# `coach_scores` maps `assessment_session_id -> overall_score` as JSON so the
# number of source sessions stays flexible. `coverage` counts the sessions that
# ranked the player; `average_score` is the rounded mean over covered sessions
# only — a player missing from a session is reported, never zero-filled (D21).
# `rank` uses standard competition ranking over the averages.
class CreateRankingConsolidationRows < ActiveRecord::Migration[8.1]
  def change
    create_table :ranking_consolidation_rows do |t|
      t.references :ranking_consolidation, null: false, foreign_key: true
      t.references :player_profile, null: false, foreign_key: true

      t.jsonb :coach_scores, null: false, default: {}
      t.integer :coverage, null: false, default: 0
      t.integer :average_score
      t.integer :rank

      t.timestamps
    end

    add_index :ranking_consolidation_rows,
              %i[ranking_consolidation_id player_profile_id],
              unique: true,
              name: "index_consolidation_rows_on_consolidation_and_player"
  end
end
