class CreatePersonAccountInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :person_account_invitations do |t|
      t.references :person, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :used_by, foreign_key: { to_table: :users }
      t.string :invitee_email, null: false
      t.string :token_digest, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :person_account_invitations, :token_digest, unique: true
    add_index :person_account_invitations, :person_id, unique: true,
              where: "status = 'active'", name: "index_person_account_invitations_one_active_per_person"
    add_check_constraint :person_account_invitations,
                         "status IN ('active', 'used', 'revoked', 'expired')",
                         name: "person_account_invitations_valid_status"
  end
end
