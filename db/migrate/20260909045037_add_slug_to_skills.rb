class AddSlugToSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :skills, :slug, :string
    add_index :skills, :slug, unique: true
    Skill.find_each(&:save!)
  end
end