require "test_helper"

class Api::V1::VideosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
    @youtube_url = "https://www.youtube.com/watch?v=LibVid1"
  end

  test "index is public and exposes the library contract" do
    Video.create!(source_url: @youtube_url)
    VideoReference.create!(video: Video.find_by!(provider_video_id: "LibVid1"),
                           referenced: drills(:one), title: "Clip")

    get "/api/v1/videos", as: :json
    assert_response :success

    body = JSON.parse(response.body)
    video = body.first
    assert_equal "youtube", video["provider"]
    assert_equal true, video["can_embed"]
    assert_equal "https://www.youtube-nocookie.com/embed/LibVid1", video["embed_url"]
    assert_equal "https://www.youtube.com/watch?v=LibVid1", video["external_url"]
    assert_equal 1, video["reference_count"]
    assert_nil video["storage_key"]
  end

  test "coach can create a standalone video from a url" do
    sign_in_as(@coach)
    assert_difference "Video.count", 1 do
      post "/api/v1/videos", params: { video: {
        source_url: @youtube_url, title: "Library clip", description: "For later use."
      } }, as: :json
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert_equal "Library clip", body["title"]
    assert_equal true, body["can_embed"]
    assert_equal 0, body["reference_count"]
  end

  test "creating the same video again reuses the record" do
    sign_in_as(@coach)
    post "/api/v1/videos", params: { video: { source_url: @youtube_url } }, as: :json
    assert_response :created
    first_id = JSON.parse(response.body)["id"]

    post "/api/v1/videos", params: { video: { source_url: "https://youtu.be/LibVid1" } }, as: :json
    assert_response :ok
    assert_equal first_id, JSON.parse(response.body)["id"]
    assert_equal 1, Video.where(provider_video_id: "LibVid1").count
  end

  test "an invalid url returns the standard validation response" do
    sign_in_as(@coach)
    post "/api/v1/videos", params: { video: { source_url: "not a url" } }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "player cannot create a video" do
    sign_in_as(@player)
    post "/api/v1/videos", params: { video: { source_url: @youtube_url } }, as: :json
    assert_response :forbidden
  end

  test "guest cannot create a video" do
    post "/api/v1/videos", params: { video: { source_url: @youtube_url } }, as: :json
    assert_response :unauthorized
  end
end
