class CreatePlayerClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :player_profiles, :display_name, :string

    create_table :player_claims do |t|
      t.references :player_profile, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :initiated_by_person, null: false, foreign_key: { to_table: :people }
      t.references :reviewed_by_person, foreign_key: { to_table: :people }
      t.string :status, null: false, default: "pending"
      t.datetime :reviewed_at
      t.text :rejection_reason
      t.timestamps
    end

    add_index :player_claims, :player_profile_id, unique: true,
              where: "status = 'pending'", name: "index_player_claims_one_pending_per_profile"
    add_check_constraint :player_claims,
                         "status IN ('pending', 'approved', 'rejected', 'cancelled')",
                         name: "player_claims_valid_status"
  end
end
