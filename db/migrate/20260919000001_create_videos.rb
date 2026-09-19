class CreateVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :videos do |t|
      # Provider identity. `provider_video_id` is NULL for uploaded (future S3)
      # videos, which are identified by `storage_key` instead.
      t.string :provider, null: false
      t.string :provider_video_id
      t.string :source_url
      t.string :storage_key

      t.string :title
      t.text :description
      t.integer :duration_seconds
      t.string :thumbnail_url

      t.references :created_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end

    add_index :videos, :provider
    add_index :videos, :provider_video_id
    # External videos are unique per provider id; S3 rows (NULL id) are exempt
    # via the partial index, so future uploads never collide.
    add_index :videos, [ :provider, :provider_video_id ],
              unique: true,
              where: "provider_video_id IS NOT NULL",
              name: "index_videos_on_provider_and_provider_video_id"
  end
end
