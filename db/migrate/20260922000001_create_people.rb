# Phase 1 of the Player/Coach identity model.
#
# Person is the domain identity of a real-world individual. Authentication
# belongs to User/Account; volleyball identity belongs to Person. A Person may
# have at most one Account, one PlayerProfile and one CoachProfile — none of
# which are mandatory.
class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.string :first_name, null: false
      t.string :last_name
      t.string :email
      t.string :phone
      t.date :date_of_birth
      t.string :status, null: false, default: "active"
      t.string :creation_source, null: false, default: "system"
      t.belongs_to :merged_into, foreign_key: { to_table: :people }
      t.belongs_to :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :people, :status
    add_index :people, :email
    add_index :people, :creation_source

    create_table :player_profiles do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.string :preferred_position
      t.string :level
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :player_profiles, :status

    create_table :coach_profiles do |t|
      t.references :person, null: false, foreign_key: true, index: { unique: true }
      t.string :coaching_level
      t.text :qualifications
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :coach_profiles, :status

    create_table :person_aliases do |t|
      t.references :person, null: false, foreign_key: true
      t.string :full_name, null: false
      t.string :alias_type

      t.timestamps
    end

    add_index :person_aliases, :full_name
  end
end