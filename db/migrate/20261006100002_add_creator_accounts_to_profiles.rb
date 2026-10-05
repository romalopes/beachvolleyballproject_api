# Keep the historical User creator FK during API compatibility while adding
# stable Account ownership for profile authorization.
class AddCreatorAccountsToProfiles < ActiveRecord::Migration[8.1]
  def up
    add_reference :player_profiles, :created_by_account, foreign_key: { to_table: :accounts } unless column_exists?(:player_profiles, :created_by_account_id)
    add_reference :coach_profiles, :created_by_account, foreign_key: { to_table: :accounts } unless column_exists?(:coach_profiles, :created_by_account_id)

    execute <<~SQL.squish
      UPDATE player_profiles AS profiles
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE profiles.created_by_id = accounts.user_id
        AND profiles.created_by_account_id IS NULL
    SQL
    execute <<~SQL.squish
      UPDATE coach_profiles AS profiles
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE profiles.created_by_id = accounts.user_id
        AND profiles.created_by_account_id IS NULL
    SQL
  end

  def down
    remove_reference :coach_profiles, :created_by_account, foreign_key: true, if_exists: true
    remove_reference :player_profiles, :created_by_account, foreign_key: true, if_exists: true
  end
end
