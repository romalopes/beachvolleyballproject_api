class CreateVideoTags < ActiveRecord::Migration[8.1]
  def change
    create_table :video_tags do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :video_tags, :name, unique: true
    add_index :video_tags, "LOWER(name)", unique: true, name: "index_video_tags_on_lower_name"
  end
end
