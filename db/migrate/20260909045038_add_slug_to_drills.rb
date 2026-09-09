class AddSlugToDrills < ActiveRecord::Migration[8.1]
  def change
    add_column :drills, :slug, :string
    add_index :drills, :slug, unique: true
    Drill.find_each(&:save!)
  end
end