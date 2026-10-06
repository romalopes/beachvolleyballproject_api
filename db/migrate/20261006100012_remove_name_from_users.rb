class RemoveNameFromUsers < ActiveRecord::Migration[8.0]
  def up
    # Preserve the legacy display name in ContactDetail before removing the
    # duplicate identity field. Existing contacts win whenever present.
    execute <<~SQL.squish
      UPDATE contact_details
      SET first_name = COALESCE(NULLIF(contact_details.first_name, ''), split_part(users.name, ' ', 1)),
          last_name = COALESCE(NULLIF(contact_details.last_name, ''), NULLIF(regexp_replace(users.name, '^\\S+\\s*', ''), ''))
      FROM accounts, users
      WHERE contact_details.account_id = accounts.id
        AND accounts.user_id = users.id
        AND users.name IS NOT NULL
    SQL

    remove_column :users, :name
  end

  def down
    add_column :users, :name, :string
    execute <<~SQL.squish
      UPDATE users
      SET name = NULLIF(trim(concat_ws(' ', contact_details.first_name, contact_details.last_name)), '')
      FROM accounts, contact_details
      WHERE accounts.user_id = users.id
        AND contact_details.account_id = accounts.id
    SQL
  end
end
