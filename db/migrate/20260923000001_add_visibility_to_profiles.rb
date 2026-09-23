# Phase C (private-to-the-coach visibility, soft variant).
#
# Ownership lives on the profile, not the Person: the `person_id` create path
# means the Person's creator may be a different coach, and one Person can hold
# a player profile and a coach profile created by different staff.
# `visibility` defaults to "shared" so nothing changes retroactively.
class AddVisibilityToProfiles < ActiveRecord::Migration[8.1]
  def change
    %i[player_profiles coach_profiles].each do |table|
      unless column_exists?(table, :visibility)
        add_column table, :visibility, :string, null: false, default: "shared"
      end
      unless column_exists?(table, :created_by_id)
        add_reference table, :created_by, foreign_key: { to_table: :users }
      end
    end

    reversible do |dir|
      dir.up do
        # Backfill the owner from the Person's author for staff-recorded
        # people (creation_source: "coach_created"). Older rows stay "shared".
        execute <<~SQL.squish
          UPDATE player_profiles
          SET created_by_id = people.created_by_id
          FROM people
          WHERE player_profiles.person_id = people.id
            AND player_profiles.created_by_id IS NULL
            AND people.creation_source = 'coach_created'
        SQL
        execute <<~SQL.squish
          UPDATE coach_profiles
          SET created_by_id = people.created_by_id
          FROM people
          WHERE coach_profiles.person_id = people.id
            AND coach_profiles.created_by_id IS NULL
            AND people.creation_source = 'coach_created'
        SQL
      end
    end

    add_index :player_profiles, :visibility unless index_exists?(:player_profiles, :visibility)
    add_index :coach_profiles, :visibility unless index_exists?(:coach_profiles, :visibility)
  end
end
