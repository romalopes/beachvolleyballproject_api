class AddProfileMergeAudit < ActiveRecord::Migration[8.1]
  def change
    %i[player_profiles coach_profiles].each do |table|
      add_column table, :archived_at, :datetime
      add_reference table, :merged_into_profile, foreign_key: { to_table: table }
      add_column table, :merged_at, :datetime
      add_reference table, :merged_by_account, foreign_key: { to_table: :accounts }
      add_check_constraint table,
                           "merged_at IS NULL OR (merged_into_profile_id IS NOT NULL AND archived_at IS NOT NULL)",
                           name: "#{table}_merge_state_consistent"
    end

    create_table :profile_merges do |t|
      t.references :source_profile, polymorphic: true, null: false, index: { unique: true, name: "index_profile_merges_unique_source" }
      t.references :canonical_profile, polymorphic: true, null: false, index: { name: "index_profile_merges_canonical" }
      t.references :merged_by_account, null: false, foreign_key: { to_table: :accounts }
      t.text :reason, null: false
      t.jsonb :reference_counts, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :profile_merges,
                         "source_profile_type = canonical_profile_type AND source_profile_id <> canonical_profile_id",
                         name: "profile_merges_distinct_same_type"
  end
end
