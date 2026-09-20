# Manual position entry in the video-category settings form allowed duplicates
# (two rows could share the same number, leaving the order ambiguous). Positions
# are now app-managed via drag-and-drop, so renumber every row densely while
# keeping the order the list already displays: position first, then name.
class NormalizeVideoCategoryPositions < ActiveRecord::Migration[8.1]
  def up
    VideoCategory.order(Arel.sql("position ASC, name ASC")).each_with_index do |category, index|
      category.update_columns(position: index)
    end
  end

  def down
    # The previous (possibly duplicated) values cannot be reconstructed.
  end
end
