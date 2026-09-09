class AddSlugToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :slug, :string
    add_index :categories, :slug, unique: true
    Category.find_each(&:save!)
  end
end