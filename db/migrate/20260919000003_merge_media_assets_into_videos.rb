# Phase 3 of the video system: the legacy flat `media_assets` table is merged
# into the reusable Video/VideoReference domain and then dropped.
#
# Every media asset becomes:
#   * one Video  — the actual media resource (provider detected from
#                  video_url, title/description/thumbnail carried over,
#                  uploaded_by preserved as created_by), and
#   * one VideoReference per attached drill/skill — the contextual use
#     (asset_type is folded into the reference description so no information
#     is lost).
#
# The migration is idempotent (find-or-create on both levels) and non-fatal:
# a media asset with an unusable URL is skipped with a log line rather than
# aborting the deploy. The `training_session_media_assets` join — built as a
# "future" hook — is dropped too: the polymorphic VideoReference already
# covers referencing a TrainingSession without any new table.
class MergeMediaAssetsIntoVideos < ActiveRecord::Migration[8.1]
  # The MediaAsset model no longer exists, so the legacy table is read through
  # a minimal inline model — migrations must be self-contained.
  class LegacyMediaAsset < ActiveRecord::Base
    self.table_name = "media_assets"
    belongs_to :drill, class_name: "::Drill", optional: false
    belongs_to :skill, class_name: "::Skill", optional: true
  end

  def up
    say_with_time "Migrating media_assets into videos + video_references" do
      LegacyMediaAsset.includes(:drill, :skill).find_each do |asset|
        next if asset.video_url.blank?

        analysis = VideoProviders.analyze(asset.video_url)
        if analysis.nil?
          Rails.logger.warn(
            "Skipping media asset #{asset.id} (#{asset.title.inspect}): " \
            "#{asset.video_url.inspect} is not a recognizable video URL"
          )
          next
        end

        video =
          if analysis.video_id
            Video.find_by(provider: analysis.provider_name, provider_video_id: analysis.video_id)
          else
            Video.find_by(provider: analysis.provider_name, source_url: analysis.normalized_url)
          end
        video ||=
          Video.create!(
            source_url: analysis.normalized_url,
            title: asset.title,
            description: asset.description,
            thumbnail_url: asset.thumbnail_url,
            created_by_id: asset.uploaded_by_id,
          )

        [ asset.drill, asset.skill ].compact.each do |referenced|
          VideoReference.find_or_create_by!(video: video, referenced: referenced) do |reference|
            reference.title = asset.title
            reference.description = [ asset.asset_type, asset.description ].compact.join(" — ").presence
          end
        end
      end
      LegacyMediaAsset.count
    end

    drop_table :training_session_media_assets
    drop_table :media_assets
  end

  def down
    create_table :training_session_media_assets do |t|
      t.references :training_session, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: true
      t.integer :position
      t.string :title

      t.timestamps
    end
    add_index :training_session_media_assets, [ :training_session_id, :media_asset_id ],
              unique: true, name: "index_training_session_media_assets_on_session_and_asset"

    create_table :media_assets do |t|
      t.string :slug
      t.string :title
      t.text :description
      t.string :video_url
      t.string :asset_type
      t.string :thumbnail_url
      t.references :drill, null: false, foreign_key: true
      t.references :skill, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :media_assets, :slug, unique: true
    # The merged data is not restored; rollback only restores the empty schema.
  end
end
