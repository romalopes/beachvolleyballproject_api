class AddAccountClaimantsToPlayerClaims < ActiveRecord::Migration[8.1]
  def up
    add_reference :player_claims, :claimant_account, foreign_key: { to_table: :accounts }
    add_reference :player_claims, :reviewed_by_account, foreign_key: { to_table: :accounts }

    execute <<~SQL.squish
      UPDATE player_claims
      SET claimant_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = player_claims.person_id
        AND player_claims.claimant_account_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE player_claims
      SET reviewed_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = player_claims.reviewed_by_person_id
        AND player_claims.reviewed_by_account_id IS NULL
    SQL

    remove_index :player_claims, name: "index_player_claims_one_pending_per_claimable"
    add_index :player_claims, [ :claimable_type, :claimable_id, :claimant_account_id ],
              unique: true, where: "status = 'pending' AND claimant_account_id IS NOT NULL",
              name: "index_player_claims_pending_per_account_and_claimable"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Account claims may contain legitimate competing pending requests that the old unique index cannot represent."
  end
end
