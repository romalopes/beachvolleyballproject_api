# Video tag ordering: tags become drag-and-drop ordered in the settings page,
# so they need the same `position` column video_categories already has.
#
# The backfill preserves today's alphabetical listing as the initial order, so
# nothing visibly moves until an admin drags a row.
class AddPositionToVideoTags < ActiveRecord::Migration[8.1]
  def up
    add_column :video_tags, :position, :integer, default: 0, null: false
    add_index :video_tags, :position

    VideoTag.reset_column_information
    VideoTag.order(:name).each_with_index do |tag, index|
      tag.update_columns(position: index)
    end
  end

  def down
    remove_index :video_tags, :position
    remove_column :video_tags, :position
  end
end
