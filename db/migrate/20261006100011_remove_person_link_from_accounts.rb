class RemovePersonLinkFromAccounts < ActiveRecord::Migration[8.1]
  def up
    missing_contact_details = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM accounts
      LEFT JOIN contact_details ON contact_details.account_id = accounts.id
      WHERE contact_details.id IS NULL
    SQL
    if missing_contact_details.positive?
      raise "Cannot remove accounts.person_id while #{missing_contact_details} Accounts lack ContactDetails"
    end

    conflicting_profile_owners = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (
        SELECT profiles.id
        FROM player_profiles profiles
        INNER JOIN accounts ON accounts.person_id = profiles.person_id
        WHERE profiles.account_id IS NOT NULL AND profiles.account_id <> accounts.id
        UNION ALL
        SELECT profiles.id
        FROM coach_profiles profiles
        INNER JOIN accounts ON accounts.person_id = profiles.person_id
        WHERE profiles.account_id IS NOT NULL AND profiles.account_id <> accounts.id
      ) conflicts
    SQL
    if conflicting_profile_owners.positive?
      raise "Cannot remove accounts.person_id while #{conflicting_profile_owners} legacy profile-to-Account mappings conflict"
    end

    # Memberships remain roster history and may include people without an
    # Account. Add the Account actor alongside the legacy roster subject so
    # authenticated authorization no longer resolves through accounts.person_id.
    add_reference :organisation_memberships, :account, foreign_key: true
    add_reference :group_memberships, :account, foreign_key: true
    add_reference :organisations, :created_by_account, foreign_key: { to_table: :accounts }
    add_reference :player_claims, :initiated_by_account, foreign_key: { to_table: :accounts }
    add_reference :player_claim_invitations, :created_by_account, foreign_key: { to_table: :accounts }
    add_reference :player_claim_invitations, :used_by_account, foreign_key: { to_table: :accounts }
    execute <<~SQL
      UPDATE organisation_memberships memberships
      SET account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = memberships.person_id
    SQL
    execute <<~SQL
      UPDATE player_profiles profiles
      SET account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = profiles.person_id AND profiles.account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE coach_profiles profiles
      SET account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = profiles.person_id AND profiles.account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE player_profiles profiles
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.user_id = profiles.created_by_id AND profiles.created_by_account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE coach_profiles profiles
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.user_id = profiles.created_by_id AND profiles.created_by_account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE player_claims claims
      SET claimant_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = claims.person_id AND claims.claimant_account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE group_memberships memberships
      SET account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = memberships.person_id
    SQL
    execute <<~SQL
      UPDATE organisations records
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = records.created_by_person_id
    SQL
    execute <<~SQL
      UPDATE player_claims claims
      SET initiated_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = claims.initiated_by_person_id
    SQL
    execute <<~SQL
      UPDATE player_claims claims
      SET reviewed_by_account_id = accounts.id
      FROM accounts
      WHERE claims.reviewed_by_person_id = accounts.person_id
        AND claims.reviewed_by_account_id IS NULL
    SQL
    execute <<~SQL
      UPDATE player_claim_invitations invitations
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = invitations.created_by_person_id
    SQL
    execute <<~SQL
      UPDATE player_claim_invitations invitations
      SET used_by_account_id = accounts.id
      FROM accounts
      WHERE accounts.person_id = invitations.used_by_person_id
    SQL
    change_column_null :organisation_memberships, :person_id, true
    change_column_null :group_memberships, :person_id, true
    change_column_null :player_claims, :person_id, true
    change_column_null :player_claims, :initiated_by_person_id, true
    change_column_null :player_claim_invitations, :created_by_person_id, true
    add_index :organisation_memberships, [ :organisation_id, :account_id ], unique: true,
      where: "account_id IS NOT NULL", name: "index_org_memberships_on_org_and_account"
    add_index :group_memberships, [ :group_id, :account_id ], unique: true,
      where: "account_id IS NOT NULL", name: "index_group_memberships_on_group_and_account"

    execute <<~SQL
      UPDATE player_profiles SET display_name = concat_ws(' ', people.first_name, people.last_name)
      FROM people WHERE player_profiles.person_id = people.id
        AND (player_profiles.display_name IS NULL OR trim(player_profiles.display_name) = '')
    SQL
    execute <<~SQL
      UPDATE coach_profiles SET display_name = concat_ws(' ', people.first_name, people.last_name)
      FROM people WHERE coach_profiles.person_id = people.id
        AND (coach_profiles.display_name IS NULL OR trim(coach_profiles.display_name) = '')
    SQL

    remove_reference :accounts, :person, foreign_key: true, index: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Account identity is now stored in ContactDetails and profile links; reconstructing accounts.person_id is ambiguous"
  end
end
