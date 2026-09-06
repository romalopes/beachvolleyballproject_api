class CreateDrillSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :drill_skills do |t|
      t.references :drill, null: false, foreign_key: true, index: false
      t.references :skill, null: false, foreign_key: true, index: false

      t.timestamps
    end

    add_index :drill_skills, [:drill_id, :skill_id], unique: true
    add_index :drill_skills, :skill_id
  end
end
