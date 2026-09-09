class AddSlugToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :media_assets, :slug, :string
    add_index :media_assets, :slug, unique: true
    MediaAsset.find_each(&:save!)
  end
end