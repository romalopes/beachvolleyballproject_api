# Reverses Phase 2's `require_person_for_coach_profiles` migration.
#
# That migration made `coach_profiles.person_id` NOT NULL because "coach profiles
# have no unassigned-coach workflow". Phase 18 adds one, so a coach recorded by
# a club with only a display name can claim the profile later — the same story a
# player has had since Phase 3.
#
# `display_name` mirrors `player_profiles.display_name`: it is required exactly
# when the profile has no Person, and is the only thing the candidate finder can
# match on before the coach has signed in.
class AllowPersonlessCoachProfiles < ActiveRecord::Migration[8.1]
  def change
    change_column_null :coach_profiles, :person_id, true
    add_column :coach_profiles, :display_name, :string
  end
end
