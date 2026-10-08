class AddEmailToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :player_profiles, :email, :string
    add_column :coach_profiles, :email, :string
  end
end
