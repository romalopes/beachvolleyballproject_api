require "test_helper"

class Api::V1::VideoReferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)    # coach + admin
    @coach = users(:three)  # coach role only
    @player = users(:one)   # player role only
    @drill = drills(:one)
    @other_drill = drills(:two)
    @skill = skills(:one)
    @youtube_url = "https://www.youtube.com/watch?v=ServeVid1"
  end

  # --- Create ---

  test "coach can add a video reference to a drill from an external url" do
    sign_in_as(@coach)
    assert_difference [ "Video.count", "VideoReference.count" ], 1 do
      post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
        video: { source_url: @youtube_url, title: "Serve receive fundamentals" },
        start_seconds: 272, end_seconds: 378,
        title: "Platform angle", description: "Focus on the platform angle."
      } }, as: :json
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert_equal 272, body["start_seconds"]
    assert_equal 378, body["end_seconds"]
    assert_equal true, body["can_embed"]
    assert_equal "https://www.youtube-nocookie.com/embed/ServeVid1?start=272&end=378", body["embed_url"]
    assert_equal "https://www.youtube.com/watch?v=ServeVid1", body["external_url"]
    assert_equal "Platform angle", body["title"]
    assert_equal "youtube", body.dig("video", "provider")
    assert_equal "YouTube", body.dig("video", "provider_label")
    assert_equal "https://i.ytimg.com/vi/ServeVid1/hqdefault.jpg", body.dig("video", "thumbnail_url")
    assert_nil body.dig("video", "storage_key")
  end

  test "adding the same external video to another drill reuses the video record" do
    sign_in_as(@coach)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }
    } }, as: :json
    assert_response :created

    assert_no_difference "Video.count" do
      post "/api/v1/drills/#{@other_drill.id}/video_references", params: { video_reference: {
        video: { source_url: "https://youtu.be/ServeVid1" }
      } }, as: :json
    end
    assert_response :created
    assert_equal Video.find_by(source_url: "https://www.youtube.com/watch?v=ServeVid1").id,
                 JSON.parse(response.body).dig("video", "id")
  end

  test "coach can add a video reference to a skill" do
    sign_in_as(@coach)
    assert_difference "VideoReference.count", 1 do
      post "/api/v1/skills/#{@skill.id}/video_references", params: { video_reference: {
        video: { source_url: "https://vimeo.com/123456789" }, start_seconds: 60
      } }, as: :json
    end
    assert_response :created
    assert_equal "vimeo", JSON.parse(response.body).dig("video", "provider")
  end

  test "an existing video can be referenced by id" do
    video = Video.create!(source_url: @youtube_url, created_by: @coach)
    sign_in_as(@coach)
    assert_no_difference "Video.count" do
      post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
        video_id: video.id, start_seconds: 0, end_seconds: 5
      } }, as: :json
    end
    assert_response :created
  end

  test "instagram references are stored but never marked embeddable" do
    sign_in_as(@coach)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: "https://www.instagram.com/p/Cabc123/" }
    } }, as: :json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal false, body["can_embed"]
    assert_nil body["embed_url"]
    assert_equal "https://www.instagram.com/p/Cabc123/", body["external_url"]
  end

  # --- Update / Delete ---

  test "creator can update the reference fields" do
    video = Video.create!(source_url: @youtube_url, created_by: @coach)
    reference = VideoReference.create!(video: video, referenced: @drill, start_seconds: 0)
    sign_in_as(@coach)
    patch "/api/v1/drills/#{@drill.id}/video_references/#{reference.id}", params: { video_reference: {
      title: "Updated clip", description: "New note", start_seconds: 10,
      end_seconds: 25, position: 3
    } }, as: :json
    assert_response :success
    reference.reload
    assert_equal [ "Updated clip", 10, 25, 3 ],
                 [ reference.title, reference.start_seconds, reference.end_seconds, reference.position ]
  end

  test "another user cannot update or destroy someone else's reference" do
    video = Video.create!(source_url: @youtube_url, created_by: @coach)
    reference = VideoReference.create!(video: video, referenced: @drill)
    sign_in_as(@admin)
    # Admins may manage shared content…
    patch "/api/v1/drills/#{@drill.id}/video_references/#{reference.id}", params: { video_reference: { title: "x" } }, as: :json
    assert_response :success

    sign_in_as(@player)
    patch "/api/v1/drills/#{@drill.id}/video_references/#{reference.id}", params: { video_reference: { title: "x" } }, as: :json
    assert_response :forbidden
    delete "/api/v1/drills/#{@drill.id}/video_references/#{reference.id}", as: :json
    assert_response :forbidden
  end

  test "destroy removes only the reference, never the shared video" do
    video = Video.create!(source_url: @youtube_url, created_by: @coach)
    reference = VideoReference.create!(video: video, referenced: @drill)
    VideoReference.create!(video: video, referenced: @other_drill)
    sign_in_as(@coach)

    assert_difference "VideoReference.count", -1 do
      assert_no_difference "Video.count" do
        delete "/api/v1/drills/#{@drill.id}/video_references/#{reference.id}", as: :json
      end
    end
    assert_response :no_content
  end

  # --- Authorization ---

  test "player cannot create a reference" do
    sign_in_as(@player)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }
    } }, as: :json
    assert_response :forbidden
  end

  test "guest cannot create a reference" do
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }
    } }, as: :json
    assert_response :unauthorized
  end

  # --- Invalid input ---

  test "an invalid url returns the standard validation response" do
    sign_in_as(@coach)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: "not a url" }
    } }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].any?
  end

  test "negative timestamps return the standard validation response" do
    sign_in_as(@coach)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }, start_seconds: -1
    } }, as: :json
    assert_response :unprocessable_entity
  end

  test "end before start returns the standard validation response" do
    sign_in_as(@coach)
    post "/api/v1/drills/#{@drill.id}/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }, start_seconds: 300, end_seconds: 200
    } }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].join.downcase.include?("end seconds")
  end

  test "nonexistent drill returns not found" do
    sign_in_as(@coach)
    post "/api/v1/drills/0/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }
    } }, as: :json
    assert_response :not_found
  end

  test "nonexistent skill returns not found" do
    sign_in_as(@coach)
    post "/api/v1/skills/0/video_references", params: { video_reference: {
      video: { source_url: @youtube_url }
    } }, as: :json
    assert_response :not_found
  end

  test "unknown reference id returns not found" do
    video = Video.create!(source_url: @youtube_url, created_by: @coach)
    reference = VideoReference.create!(video: video, referenced: @drill)
    sign_in_as(@coach)
    patch "/api/v1/drills/#{@other_drill.id}/video_references/#{reference.id}",
          params: { video_reference: { title: "x" } }, as: :json
    assert_response :not_found
  end

  # --- Read contract (drill/skill show) ---

  test "drill show exposes video_references with the stable contract" do
    VideoReference.create!(video: Video.create!(source_url: @youtube_url),
                           referenced: @drill, start_seconds: 272, end_seconds: 378)
    get "/api/v1/drills/#{@drill.slug}", as: :json
    assert_response :success

    reference = JSON.parse(response.body)["video_references"].first
    assert_equal 272, reference["start_seconds"]
    assert_equal 378, reference["end_seconds"]
    assert_equal true, reference["can_embed"]
    assert_includes reference["embed_url"], "/embed/ServeVid1"
    assert_equal "https://www.youtube.com/watch?v=ServeVid1", reference["external_url"]
    assert_equal "youtube", reference.dig("video", "provider")
    assert reference.key?("position")
  end

  test "skill show exposes video_references with the stable contract" do
    VideoReference.create!(video: Video.create!(source_url: "https://cdn.example.com/clip.mp4"),
                           referenced: @skill, title: "Demo clip")
    get "/api/v1/skills/#{@skill.slug}", as: :json
    assert_response :success

    reference = JSON.parse(response.body)["video_references"].first
    assert_equal false, reference["can_embed"]
    assert_equal "https://cdn.example.com/clip.mp4", reference["external_url"]
    assert_equal "external", reference.dig("video", "provider")
  end
end
