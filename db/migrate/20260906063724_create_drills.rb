class CreateDrills < ActiveRecord::Migration[8.1]
  def change
    create_table :drills do |t|
      t.string :title
      t.text :setup_instructions
      t.integer :player_count
      t.string :difficulty_level

      t.timestamps
    end
  end
end
