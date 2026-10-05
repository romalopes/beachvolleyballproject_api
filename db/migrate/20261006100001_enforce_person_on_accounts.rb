# Phase 1 of issue 225: guarantee that every persisted Account points to one
# Person. Unlike the historical migration, this explicitly backfills only null
# links and then applies the non-null constraint.
class EnforcePersonOnAccounts < ActiveRecord::Migration[8.1]
  class AccountRow < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class UserRow < ActiveRecord::Base
    self.table_name = "users"
  end

  class PersonRow < ActiveRecord::Base
    self.table_name = "people"
  end

  def up
    AccountRow.reset_column_information
    UserRow.reset_column_information
    PersonRow.reset_column_information

    AccountRow.where(person_id: nil).find_each do |account|
      user = UserRow.find(account.user_id)
      first_name, last_name = split_name(user.name)
      now = Time.current
      person = PersonRow.create!(
        first_name: first_name.presence || "Account #{account.id}",
        last_name: last_name,
        email: user.email_address,
        status: "active",
        creation_source: "system",
        created_by_id: user.id,
        created_at: now,
        updated_at: now
      )
      account.update_columns(person_id: person.id, updated_at: now)
    end

    remaining = AccountRow.where(person_id: nil).count
    raise "Cannot enforce accounts.person_id: #{remaining} null Account links remain" if remaining.positive?

    change_column_null :accounts, :person_id, false
  end

  def down
    # Keep any generated Person rows. Relaxing the constraint is reversible;
    # deleting or unlinking identity data is deliberately not.
    change_column_null :accounts, :person_id, true
  end

  private

  def split_name(value)
    parts = value.to_s.strip.split(/\s+/, 2)
    [ parts.shift, parts.first ]
  end
end
