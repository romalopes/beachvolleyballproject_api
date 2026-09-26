# Phase 4 (Ranking Consolidation), plan §8: one frozen row per
# consolidation/source-session pair, capturing that session's ranking at the
# moment of consolidation.
#
# `ranking_snapshot` stores the session's complete player entries
# (`player_profile_id`, `overall_score`, `rank`) as JSON so the consolidation
# never changes when the source session later changes. The join itself carries
# no scores — it points at the snapshot.
class CreateRankingConsolidationSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :ranking_consolidation_sessions do |t|
      t.references :ranking_consolidation, null: false, foreign_key: true
      t.references :assessment_session, null: false, foreign_key: true

      t.jsonb :ranking_snapshot, null: false, default: []

      t.timestamps
    end

    add_index :ranking_consolidation_sessions,
              %i[ranking_consolidation_id assessment_session_id],
              unique: true,
              name: "index_consolidation_sessions_on_consolidation_and_session"
  end
end
