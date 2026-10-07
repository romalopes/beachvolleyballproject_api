# frozen_string_literal: true

# Contracts the legacy Person identity layer. An Account is now the durable
# domain identity whether or not a login User has claimed it; ContactDetail owns
# the private fields that previously lived on people.
class RetirePeopleInFavorOfAccounts < ActiveRecord::Migration[8.1]
  def up
    change_column_null :accounts, :user_id, true

    # Preserve one Account for every recorded Person. Existing profile and
    # membership account links win; an accountless Person receives an Account
    # without a User and can later be claimed by attaching a login User.
    create_table :person_account_cutover_maps, id: false do |t|
      t.bigint :person_id, null: false
      # A Person without a profile or membership has no Account yet. It is
      # populated after the matching Account row is inserted below.
      t.bigint :account_id
    end
    add_index :person_account_cutover_maps, :person_id, unique: true
    add_index :person_account_cutover_maps, :account_id

    execute <<~SQL
      INSERT INTO person_account_cutover_maps (person_id, account_id)
      SELECT people.id, COALESCE(
        (SELECT account_id FROM player_profiles WHERE person_id = people.id AND account_id IS NOT NULL ORDER BY id LIMIT 1),
        (SELECT account_id FROM coach_profiles WHERE person_id = people.id AND account_id IS NOT NULL ORDER BY id LIMIT 1),
        (SELECT account_id FROM organisation_memberships WHERE person_id = people.id AND account_id IS NOT NULL ORDER BY id LIMIT 1),
        (SELECT account_id FROM group_memberships WHERE person_id = people.id AND account_id IS NOT NULL ORDER BY id LIMIT 1)
      )
      FROM people
    SQL

    execute <<~SQL
      INSERT INTO accounts (created_at, updated_at)
      SELECT CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM person_account_cutover_maps
      WHERE account_id IS NULL
    SQL

    # PostgreSQL assigns ids in insertion order; pair the newly created rows
    # deterministically with the unmatched People rows.
    execute <<~SQL
      WITH unmatched AS (
        SELECT person_id, row_number() OVER (ORDER BY person_id) AS row_number
        FROM person_account_cutover_maps WHERE account_id IS NULL
      ), created AS (
        SELECT id, row_number() OVER (ORDER BY id DESC) AS reverse_number
        FROM accounts WHERE user_id IS NULL
      ), created_count AS (SELECT COUNT(*) AS count FROM unmatched)
      UPDATE person_account_cutover_maps map
      SET account_id = created.id
      FROM unmatched
      CROSS JOIN created_count
      JOIN created ON created.reverse_number = created_count.count - unmatched.row_number + 1
      WHERE map.person_id = unmatched.person_id
    SQL

    execute <<~SQL
      INSERT INTO contact_details (account_id, first_name, last_name, email, phone, date_of_birth, created_at, updated_at)
      SELECT map.account_id, people.first_name, people.last_name, people.email, people.phone, people.date_of_birth,
             CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM person_account_cutover_maps map
      JOIN people ON people.id = map.person_id
      WHERE NOT EXISTS (SELECT 1 FROM contact_details WHERE contact_details.account_id = map.account_id)
    SQL

    # Existing Account contact data is retained unless a legacy value is absent.
    execute <<~SQL
      UPDATE contact_details details
      SET first_name = COALESCE(NULLIF(details.first_name, ''), people.first_name),
          last_name = COALESCE(NULLIF(details.last_name, ''), people.last_name),
          email = COALESCE(NULLIF(details.email, ''), people.email),
          phone = COALESCE(NULLIF(details.phone, ''), people.phone),
          date_of_birth = COALESCE(details.date_of_birth, people.date_of_birth),
          updated_at = CURRENT_TIMESTAMP
      FROM person_account_cutover_maps map
      JOIN people ON people.id = map.person_id
      WHERE details.account_id = map.account_id
    SQL

    map_person_references
    remove_legacy_person_references
    drop_table :person_account_cutover_maps
    drop_table :people
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "People data is now Account/ContactDetail data"
  end

  private

  def map_person_references
    %w[player_profiles coach_profiles organisation_memberships group_memberships].each do |table|
      execute <<~SQL
        UPDATE #{quote_table_name(table)} records
        SET account_id = map.account_id
        FROM person_account_cutover_maps map
        WHERE records.person_id = map.person_id
      SQL
    end

    execute <<~SQL
      UPDATE organisations records SET created_by_account_id = map.account_id
      FROM person_account_cutover_maps map WHERE records.created_by_person_id = map.person_id
    SQL
    execute <<~SQL
      UPDATE player_claims records SET claimant_account_id = map.account_id
      FROM person_account_cutover_maps map WHERE records.person_id = map.person_id
    SQL
    %w[initiated reviewed].each do |role|
      execute <<~SQL
        UPDATE player_claims records SET #{role}_by_account_id = map.account_id
        FROM person_account_cutover_maps map WHERE records.#{role}_by_person_id = map.person_id
      SQL
    end
  end

  def remove_legacy_person_references
    # Person-targeted invitations were superseded by profile invitations. Their
    # polymorphic subject has no database foreign key, so remove those retired
    # tokens before dropping the subject table.
    execute "DELETE FROM claim_invitations WHERE claimable_type = 'Person'"

    remove_reference :player_profiles, :person, foreign_key: true
    remove_reference :coach_profiles, :person, foreign_key: true
    remove_reference :organisation_memberships, :person, foreign_key: true
    remove_reference :group_memberships, :person, foreign_key: true
    remove_reference :organisations, :created_by_person, foreign_key: { to_table: :people }
    remove_reference :player_claims, :person, foreign_key: { to_table: :people }
    remove_reference :player_claims, :initiated_by_person, foreign_key: { to_table: :people }
    remove_reference :player_claims, :reviewed_by_person, foreign_key: { to_table: :people }

    drop_table :person_aliases if table_exists?(:person_aliases)
    drop_table :person_consolidations if table_exists?(:person_consolidations)
    drop_table :person_account_invitations if table_exists?(:person_account_invitations)
    drop_table :player_claim_invitations if table_exists?(:player_claim_invitations)
  end
end
