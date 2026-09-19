class CreateVideoCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :video_categories do |t|
      t.string :name, null: false
      t.text :description
      t.integer :position, default: 0, null: false
      t.references :created_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :video_categories, :name, unique: true
    add_index :video_categories, :position
  end
end
