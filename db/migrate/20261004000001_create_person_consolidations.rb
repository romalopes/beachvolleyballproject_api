class CreatePersonConsolidations < ActiveRecord::Migration[8.1]
  def change
    add_reference :people, :merged_by, foreign_key: { to_table: :users }
    add_column :people, :merged_at, :datetime

    create_table :person_consolidations do |t|
      t.references :source_person, null: false, foreign_key: { to_table: :people }, index: { unique: true }
      t.references :canonical_person, null: false, foreign_key: { to_table: :people }
      t.references :performed_by, null: false, foreign_key: { to_table: :users }
      t.jsonb :result, null: false, default: {}
      t.datetime :completed_at, null: false
      t.timestamps
    end

    add_check_constraint :person_consolidations, "source_person_id <> canonical_person_id", name: "person_consolidations_distinct_people"
  end
end
