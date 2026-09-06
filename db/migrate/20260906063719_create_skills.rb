class CreateSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills do |t|
      t.string :title
      t.references :category, null: false, foreign_key: true
      t.text :description

      t.timestamps
    end
  end
end
