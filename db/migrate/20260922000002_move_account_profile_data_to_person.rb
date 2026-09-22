# Phase 1 backfill: move personal profile data from Account to Person.
#
# Account was carrying first_name/last_name/phone/date_of_birth, which are
# attributes of the real-world person, not of the authentication account.
# Every existing Account receives a Person with that data copied over; the
# contact email comes from the User. Afterwards the columns are removed from
# accounts and the account -> person link becomes mandatory and unique.
class MoveAccountProfileDataToPerson < ActiveRecord::Migration[8.1]
  class BackfillPerson < ActiveRecord::Base
    self.table_name = "people"
  end

  class BackfillAccount < ActiveRecord::Base
    self.table_name = "accounts"
    belongs_to :backfill_user, class_name: "BackfillUser", foreign_key: :user_id
    belongs_to :person, class_name: "BackfillPerson", optional: true
  end

  class BackfillUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    unless column_exists?(:accounts, :person_id)
      add_reference :accounts, :person, foreign_key: true, index: { unique: true }
    end

    BackfillAccount.reset_column_information
    BackfillPerson.reset_column_information

    BackfillAccount.includes(:backfill_user).find_each do |account|
      next unless account.backfill_user
      user = account.backfill_user
      first_name, last_name = split_name(account[:first_name].presence || user.name)

      BackfillPerson.create!(
        first_name: first_name || "Unknown",
        last_name: last_name,
        email: user.email_address,
        phone: account[:phone],
        date_of_birth: account[:date_of_birth],
        status: "active",
        creation_source: "signup",
        created_by_id: user.id
      ).then { |person| account.update_column(:person_id, person.id) }
    end

    change_column_null :accounts, :person_id, false unless accounts_person_id_is_nullable?
    remove_column :accounts, :first_name, if_exists: true
    remove_column :accounts, :last_name, if_exists: true
    remove_column :accounts, :phone, if_exists: true
    remove_column :accounts, :date_of_birth, if_exists: true
  end

  def down
    add_column :accounts, :first_name, :string unless column_exists?(:accounts, :first_name)
    add_column :accounts, :last_name, :string unless column_exists?(:accounts, :last_name)
    add_column :accounts, :phone, :string unless column_exists?(:accounts, :phone)
    add_column :accounts, :date_of_birth, :date unless column_exists?(:accounts, :date_of_birth)

    BackfillAccount.reset_column_information
    BackfillPerson.reset_column_information

    BackfillAccount.includes(:person).find_each do |account|
      person = account.person
      next unless person

      account.update_columns(
        first_name: person.first_name,
        last_name: person.last_name,
        phone: person.phone,
        date_of_birth: person.date_of_birth
      )
    end

    remove_index :accounts, :person_id, if_exists: true
    remove_reference :accounts, :person, foreign_key: true, if_exists: true
  end

  private

  def split_name(name)
    return [ nil, nil ] if name.blank?
    parts = name.strip.split(/\s+/, 2)
    [ parts[0], parts[1] ]
  end

  def accounts_person_id_is_nullable?
    row = execute("SELECT is_nullable FROM information_schema.columns WHERE table_name = 'accounts' AND column_name = 'person_id'").first
    row && row["is_nullable"] == "YES"
  end
end
