class CreatePlayerClaimInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :player_claim_invitations do |t|
      t.references :player_profile, null: false, foreign_key: true
      t.references :created_by_person, null: false, foreign_key: { to_table: :people }
      t.references :used_by_person, foreign_key: { to_table: :people }
      t.string :token_digest, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :player_claim_invitations, :token_digest, unique: true
    add_index :player_claim_invitations, :player_profile_id, unique: true,
              where: "status = 'active'", name: "index_player_claim_invitations_one_active_per_profile"
    add_check_constraint :player_claim_invitations,
                         "status IN ('active', 'used', 'revoked', 'expired')",
                         name: "player_claim_invitations_valid_status"
  end
end
