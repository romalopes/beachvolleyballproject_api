class CreateVideoTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :video_taggings do |t|
      t.references :video, null: false, foreign_key: true
      t.references :video_tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :video_taggings, [ :video_id, :video_tag_id ], unique: true, name: "index_video_taggings_on_video_id_and_video_tag_id"
  end
end
