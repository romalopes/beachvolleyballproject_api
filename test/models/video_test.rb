require "test_helper"

class VideoTest < ActiveSupport::TestCase
  # --- Provider detection / identity ---

  test "accepts a youtube video and stores its normalized identity" do
    video = Video.new(source_url: "https://youtu.be/ABC123")
    assert video.valid?
    assert_equal "youtube", video.provider
    assert_equal "ABC123", video.provider_video_id
    assert_equal "https://www.youtube.com/watch?v=ABC123", video.source_url
    assert_equal "https://i.ytimg.com/vi/ABC123/hqdefault.jpg", video.thumbnail_url
  end

  test "accepts vimeo, instagram, tiktok and external videos" do
    cases = {
      "https://vimeo.com/123456789" => [ "vimeo", "123456789" ],
      "https://www.instagram.com/p/Cabc123/" => [ "instagram", "Cabc123" ],
      "https://www.tiktok.com/@coach/video/7123456789012345678" => [ "tiktok", "7123456789012345678" ],
      "https://cdn.example.com/clip.mp4" => [ "external", nil ]
    }
    cases.each do |url, (provider, video_id)|
      video = Video.new(source_url: url)
      assert video.valid?, "#{url} should be valid: #{video.errors.full_messages}"
      assert_equal provider, video.provider
      if video_id
        assert_equal video_id, video.provider_video_id
      else
        assert_nil video.provider_video_id
      end
    end
  end

  test "rejects invalid urls" do
    [ "not a url", "javascript:alert(1)", "ftp://example.com/clip.mp4" ].each do |url|
      video = Video.new(source_url: url)
      assert_not video.valid?
      assert video.errors[:source_url].any?
    end
  end

  test "rejects a video without source url or storage key" do
    video = Video.new
    assert_not video.valid?
    assert video.errors[:base].any?
  end

  test "accepts a future s3 video identified only by storage key" do
    video = Video.new(provider: "s3", storage_key: "videos/clip.mp4")
    assert video.valid?, video.errors.full_messages.to_sentence
    assert_equal "videos/clip.mp4", video.storage_key
  end

  test "a stored s3-like video can embed nothing but keeps its storage key" do
    video = Video.new(provider: "s3", storage_key: "videos/clip.mp4")
    assert_not video.can_embed?
    assert_nil video.embed_url
  end

  # --- Reuse ---

  test "find_or_create_from_url! reuses the video for the same clip" do
    first = Video.find_or_create_from_url!("https://youtu.be/ABC123")
    assert_not_nil first

    second = Video.find_or_create_from_url!("https://www.youtube.com/watch?v=ABC123")
    assert_equal first.id, second.id
    assert_equal 1, Video.where(provider_video_id: "ABC123").count
  end

  test "find_or_create_from_url! returns nil for an invalid url" do
    assert_nil Video.find_or_create_from_url!("not a url")
  end

  # --- Playback capabilities ---

  test "youtube video can embed and builds timestamped embed urls" do
    video = Video.create!(source_url: "https://www.youtube.com/watch?v=ABC123")
    assert video.can_embed?
    assert_equal "https://www.youtube-nocookie.com/embed/ABC123?start=272&end=378",
                 video.embed_url(272, 378)
    assert_equal "YouTube", video.provider_label
  end

  test "instagram video can never embed and falls back to a watch link" do
    video = Video.create!(source_url: "https://www.instagram.com/p/Cabc123/")
    assert_not video.can_embed?
    assert_nil video.embed_url
    assert_equal "https://www.instagram.com/p/Cabc123/", video.external_url
    assert_equal "Instagram", video.provider_label
  end
end
