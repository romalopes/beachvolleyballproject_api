class AddVideoCategoryToVideos < ActiveRecord::Migration[8.1]
  def up
    add_column :videos, :video_category_id, :bigint
    add_foreign_key :videos, :video_categories, column: :video_category_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :videos, to_table: :video_categories, column: :video_category_id
    remove_column :videos, :video_category_id
  end
end
