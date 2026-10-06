class AddAccountCentricIdentityLinks < ActiveRecord::Migration[8.1]
  def up
    create_table :contact_details do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :restrict }
      t.string :first_name, null: false
      t.string :last_name
      t.string :email
      t.string :phone
      t.date :date_of_birth
      t.timestamps
    end

    add_reference :player_profiles, :account, null: true, foreign_key: { on_delete: :restrict }
    add_reference :coach_profiles, :account, null: true, foreign_key: { on_delete: :restrict }

    backfill_contact_details
    backfill_profile_accounts(:player_profiles)
    backfill_profile_accounts(:coach_profiles)
    backfill_creator_accounts(:player_profiles)
    backfill_creator_accounts(:coach_profiles)
  end

  def down
    remove_reference :coach_profiles, :account, foreign_key: true
    remove_reference :player_profiles, :account, foreign_key: true
    drop_table :contact_details
  end

  private

  # Person remains in place and is the compatibility source during this phase.
  # Login email is deliberately not copied from User: `people.email` is the
  # separate contact address.
  def backfill_contact_details
    execute <<~SQL
      INSERT INTO contact_details
        (account_id, first_name, last_name, email, phone, date_of_birth, created_at, updated_at)
      SELECT accounts.id, people.first_name, people.last_name, people.email,
             people.phone, people.date_of_birth, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM accounts
      INNER JOIN people ON people.id = accounts.person_id
      WHERE NOT EXISTS (
        SELECT 1 FROM contact_details WHERE contact_details.account_id = accounts.id
      )
    SQL
  end

  def backfill_profile_accounts(profile_table)
    execute <<~SQL
      UPDATE #{quote_table_name(profile_table)} AS profiles
      SET account_id = accounts.id
      FROM accounts
      WHERE profiles.account_id IS NULL
        AND profiles.person_id = accounts.person_id
    SQL
  end

  def backfill_creator_accounts(profile_table)
    execute <<~SQL
      UPDATE #{quote_table_name(profile_table)} AS profiles
      SET created_by_account_id = accounts.id
      FROM accounts
      WHERE profiles.created_by_account_id IS NULL
        AND profiles.created_by_id = accounts.user_id
    SQL
  end
end
