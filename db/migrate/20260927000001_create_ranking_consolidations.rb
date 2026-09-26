# Phase 4 (Ranking Consolidation), plan §8: an immutable snapshot that merges
# several coaches' *published* session results into one club-level ranking.
#
# A consolidation is a judgement record, not a live view: once created it never
# changes, even if a source session is later withdrawn. Corrections are a new
# consolidation, mirroring how a published session is archival (D24).
#
# Compatibility is enforced at creation (D20): every source session must be
# published, share one assessment definition, and have complete coverage for
# every player it claims to rank. A player missing from any source session is
# reported in `missing_players`, never assigned zero (D21).
class CreateRankingConsolidations < ActiveRecord::Migration[8.1]
  def change
    create_table :ranking_consolidations do |t|
      t.references :assessment_definition, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }

      t.string :name
      t.text :notes

      t.timestamps
    end
  end
end
