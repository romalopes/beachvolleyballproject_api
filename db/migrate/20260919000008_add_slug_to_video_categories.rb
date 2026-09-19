class AddSlugToVideoCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :video_categories, :slug, :string
    add_index :video_categories, :slug, unique: true
    VideoCategory.reset_column_information
    VideoCategory.find_each do |category|
      category.slug = category.name.to_s.parameterize
      category.slug = "item" if category.slug.blank?
      base = category.slug
      count = 1
      while VideoCategory.where(slug: category.slug).where.not(id: category.id).exists?
        count += 1
        category.slug = "#{base}-#{count}"
      end
      category.update_columns(slug: category.slug)
    end
  end
end