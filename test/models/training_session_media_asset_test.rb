require "test_helper"

class TrainingSessionMediaAssetTest < ActiveSupport::TestCase
  # The media join is the future extension point (spec §24/§45): it reuses the
  # existing MediaAsset model, so this suite only pins down the association
  # behaviour. There is no media UI in this phase.
  test "belongs to a training session and an existing media asset" do
    link = TrainingSessionMediaAsset.new(
      training_session: training_sessions(:one),
      media_asset: media_assets(:one),
      position: 0,
      title: "Serve reception demo"
    )
    assert link.valid?
    assert_equal "Serve reception demo", link.title
  end

  test "requires a training session and a media asset" do
    link = TrainingSessionMediaAsset.new
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :training_session
    assert_includes link.errors.attribute_names, :media_asset
  end

  test "rejects the same media asset twice within one training" do
    TrainingSessionMediaAsset.create!(training_session: training_sessions(:one),
                                      media_asset: media_assets(:one))
    link = TrainingSessionMediaAsset.new(training_session: training_sessions(:one),
                                         media_asset: media_assets(:one))
    assert_not link.valid?
    assert_includes link.errors.attribute_names, :media_asset_id
  end

  test "keeps the intentional position order" do
    session = training_sessions(:one)
    TrainingSessionMediaAsset.create!(training_session: session, media_asset: media_assets(:two), position: 1)
    TrainingSessionMediaAsset.create!(training_session: session, media_asset: media_assets(:one), position: 0)

    assert_equal [ media_assets(:one).id, media_assets(:two).id ],
                 session.training_session_media_assets.reload.map(&:media_asset_id)
  end

  test "destroying the training removes the links but not the media assets" do
    session = training_sessions(:one)
    TrainingSessionMediaAsset.create!(training_session: session, media_asset: media_assets(:one))

    assert_difference("TrainingSessionMediaAsset.count", -1) do
      session.destroy
    end
    assert MediaAsset.exists?(media_assets(:one).id)
  end
end
