# Phase 1 backfill: move personal profile data from Account to Person.
#
# Account was carrying first_name/last_name/phone/date_of_birth, which are
# attributes of the real-world person, not of the authentication account.
# Every existing Account receives a Person with that data copied over; the
# contact email comes from the User. Afterwards the columns are removed from
# accounts and the account→person link becomes mandatory and unique.
class MoveAccountProfileDataToPerson < ActiveRecord::Migration[8.1]
  # Inline classes so the backfill does not depend on the current state of the
  # application models.
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
    # add_reference creates the index by default; make it unique in one step.
    add_reference :accounts, :person, foreign_key: true, index: { unique: true }

    BackfillAccount.reset_column_information
    BackfillPerson.reset_column_information

    BackfillAccount.includes(:backfill_user).find_each do |account|
      user = account.backfill_user
      first_name, last_name = split_name(account[:first_name].presence || user&.name)

      BackfillPerson.create!(
        first_name: first_name || "Unknown",
        last_name: last_name,
        email: user&.email_address,
        phone: account[:phone],
        date_of_birth: account[:date_of_birth],
        status: "active",
        creation_source: "signup",
        created_by_id: user&.id
      ).then { |person| account.update_column(:person_id, person.id) }
    end

    change_column_null :accounts, :person_id, false

    remove_column :accounts, :first_name
    remove_column :accounts, :last_name
    remove_column :accounts, :phone
    remove_column :accounts, :date_of_birth
  end

  def down
    add_column :accounts, :first_name, :string
    add_column :accounts, :last_name, :string
    add_column :accounts, :phone, :string
    add_column :accounts, :date_of_birth, :date

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

    remove_index :accounts, :person_id
    remove_reference :accounts, :person, foreign_key: true
  end

  private

  def split_name(name)
    return [ nil, nil ] if name.blank?

    parts = name.strip.split(/\s+/, 2)
    [ parts[0], parts[1] ]
  end
end