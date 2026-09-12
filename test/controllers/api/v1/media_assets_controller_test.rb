require "test_helper"

class Api::V1::MediaAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
    @drill = drills(:one)
    @owned = MediaAsset.create!(
      drill: @drill, title: "Owned Clip",
      video_url: "https://example.com/clip.mp4",
      asset_type: "actual_training_clip",
      uploaded_by: @coach
    )
  end

  test "index is public and includes drill and skill" do
    get "/api/v1/media_assets"
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.first.key?("drill")
  end

  test "show is public" do
    get "/api/v1/media_assets/#{media_assets(:one).id}"
    assert_response :success
    assert_equal media_assets(:one).id, JSON.parse(response.body)["id"]
  end

  test "show returns 404 for an unknown id" do
    get "/api/v1/media_assets/0"
    assert_response :not_found
    assert_equal "Media Asset not found", JSON.parse(response.body)["error"]
  end

  test "coach can create a media asset" do
    sign_in_as(@coach)
    assert_difference("MediaAsset.count") do
      post "/api/v1/media_assets", params: { media_asset: {
        drill_id: @drill.id, title: "Demo",
        video_url: "https://example.com/demo.mp4", asset_type: "example_demo"
      } }
    end
    assert_response :created
    assert_equal @coach.id, MediaAsset.find_by(title: "Demo").uploaded_by_id
  end

  test "player cannot create a media asset" do
    sign_in_as(@player)
    post "/api/v1/media_assets", params: { media_asset: {
      drill_id: @drill.id, title: "Blocked",
      video_url: "https://example.com/x.mp4", asset_type: "example_demo"
    } }
    assert_response :forbidden
  end

  test "guest cannot create a media asset" do
    post "/api/v1/media_assets", params: { media_asset: {
      drill_id: @drill.id, title: "Blocked",
      video_url: "https://example.com/x.mp4", asset_type: "example_demo"
    } }
    assert_response :unauthorized
  end

  test "create returns 422 on validation errors" do
    sign_in_as(@coach)
    post "/api/v1/media_assets", params: { media_asset: { drill_id: @drill.id, title: "" } }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "uploader can update their media asset" do
    sign_in_as(@coach)
    patch "/api/v1/media_assets/#{@owned.id}", params: { media_asset: { title: "Retitled" } }
    assert_response :success
    assert_equal "Retitled", @owned.reload.title
  end

  test "non-uploader cannot update another user's media asset" do
    sign_in_as(@player)
    patch "/api/v1/media_assets/#{@owned.id}", params: { media_asset: { title: "Hacked" } }
    assert_response :forbidden
  end

  test "admin can update any media asset" do
    sign_in_as(@admin)
    patch "/api/v1/media_assets/#{@owned.id}", params: { media_asset: { title: "Admin retitled" } }
    assert_response :success
    assert_equal "Admin retitled", @owned.reload.title
  end

  test "uploader can destroy their media asset" do
    sign_in_as(@coach)
    assert_difference("MediaAsset.count", -1) do
      delete "/api/v1/media_assets/#{@owned.id}"
    end
    assert_response :no_content
  end

  test "guest cannot destroy a media asset" do
    delete "/api/v1/media_assets/#{@owned.id}"
    assert_response :unauthorized
    assert MediaAsset.exists?(@owned.id)
  end
end
