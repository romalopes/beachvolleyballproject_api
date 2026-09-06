class CreateMediaAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :media_assets do |t|
      t.references :drill, null: false, foreign_key: true
      t.references :skill, foreign_key: true
      t.string :title
      t.text :description
      t.string :video_url
      t.string :asset_type
      t.string :thumbnail_url

      t.timestamps
    end
  end
end
