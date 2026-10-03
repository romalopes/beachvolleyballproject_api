class AllowMultipleProfilesPerPerson < ActiveRecord::Migration[8.1]
  def change
    change_column_null :player_profiles, :person_id, true
    remove_index :player_profiles, name: "index_player_profiles_on_person_id"
    add_index :player_profiles, :person_id, name: "index_player_profiles_on_person_id"

    remove_index :coach_profiles, name: "index_coach_profiles_on_person_id"
    add_index :coach_profiles, :person_id, name: "index_coach_profiles_on_person_id"
  end
end
