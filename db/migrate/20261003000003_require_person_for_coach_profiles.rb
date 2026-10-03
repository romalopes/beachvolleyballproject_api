class RequirePersonForCoachProfiles < ActiveRecord::Migration[8.1]
  def change
    # Coach profiles have no unassigned-coach workflow; the identity plan only
    # calls for nullable PlayerProfile.person_id.
    change_column_null :coach_profiles, :person_id, false
  end
end
