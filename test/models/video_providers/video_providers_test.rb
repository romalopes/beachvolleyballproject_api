require "test_helper"

class VideoProvidersTest < ActiveSupport::TestCase
  # --- YouTube ---

  test "detects youtube watch urls and normalizes them" do
    analysis = VideoProviders.analyze("https://www.youtube.com/watch?v=ABC123&list=PL1&index=2")
    assert_equal "youtube", analysis.provider_name
    assert_equal "ABC123", analysis.video_id
    assert_equal "https://www.youtube.com/watch?v=ABC123", analysis.normalized_url
  end

  test "detects youtu.be short links" do
    analysis = VideoProviders.analyze("https://youtu.be/ABC123?t=10")
    assert_equal "youtube", analysis.provider_name
    assert_equal "ABC123", analysis.video_id
  end

  test "detects youtube shorts" do
    analysis = VideoProviders.analyze("https://www.youtube.com/shorts/ABC123")
    assert_equal "youtube", analysis.provider_name
    assert_equal "ABC123", analysis.video_id
  end

  test "youtube supports embedding with start and end timestamps" do
    assert VideoProviders::YouTube.can_embed?
    assert VideoProviders::YouTube.supports_start_timestamp?
    assert VideoProviders::YouTube.supports_end_timestamp?
    assert_equal "https://www.youtube-nocookie.com/embed/ABC123?start=272&end=378",
                 VideoProviders::YouTube.embed_url("ABC123", 272, 378)
    assert_equal "https://www.youtube-nocookie.com/embed/ABC123",
                 VideoProviders::YouTube.embed_url("ABC123")
  end

  test "youtube exposes a provider thumbnail" do
    assert_equal "https://i.ytimg.com/vi/ABC123/hqdefault.jpg",
                 VideoProviders::YouTube.thumbnail_url("ABC123")
  end

  test "youtube watch link is the normalized canonical url" do
    assert_equal "https://www.youtube.com/watch?v=ABC123",
                 VideoProviders::YouTube.external_url("https://youtu.be/ABC123")
  end

  # --- Vimeo ---

  test "detects vimeo urls" do
    analysis = VideoProviders.analyze("https://vimeo.com/123456789?autoplay=1")
    assert_equal "vimeo", analysis.provider_name
    assert_equal "123456789", analysis.video_id
    assert_equal "https://vimeo.com/123456789", analysis.normalized_url
  end

  test "vimeo embeds with a start fragment but no end support" do
    assert VideoProviders::Vimeo.can_embed?
    assert VideoProviders::Vimeo.supports_start_timestamp?
    assert_not VideoProviders::Vimeo.supports_end_timestamp?
    assert_equal "https://player.vimeo.com/video/123456789#t=4m32s",
                 VideoProviders::Vimeo.embed_url("123456789", 272)
  end

  # --- Instagram ---

  test "detects instagram posts and reels" do
    %w[https://www.instagram.com/p/Cabc123/ https://www.instagram.com/reel/Cabc123/].each do |url|
      analysis = VideoProviders.analyze(url)
      assert_equal "instagram", analysis.provider_name
      assert_equal "Cabc123", analysis.video_id
    end
  end

  test "instagram normalizes the host and drops tracking params" do
    assert_equal "https://www.instagram.com/p/Cabc123/",
                 VideoProviders.analyze("https://instagram.com/p/Cabc123/?utm_source=share").normalized_url
  end

  test "instagram cannot embed and has no timestamp support" do
    assert_not VideoProviders::Instagram.can_embed?
    assert_not VideoProviders::Instagram.supports_start_timestamp?
    assert_equal "https://www.instagram.com/p/Cabc123/",
                 VideoProviders::Instagram.external_url("https://www.instagram.com/p/Cabc123/")
  end

  # --- TikTok ---

  test "detects tiktok video urls" do
    analysis = VideoProviders.analyze("https://www.tiktok.com/@coach/video/7123456789012345678?is_copy_url=1")
    assert_equal "tiktok", analysis.provider_name
    assert_equal "7123456789012345678", analysis.video_id
    assert_equal "https://www.tiktok.com/@coach/video/7123456789012345678", analysis.normalized_url
  end

  test "tiktok cannot embed and has no timestamp support" do
    assert_not VideoProviders::TikTok.can_embed?
    assert_not VideoProviders::TikTok.supports_start_timestamp?
    assert_equal "https://www.tiktok.com/@coach/video/7123456789012345678",
                 VideoProviders::TikTok.external_url("https://www.tiktok.com/@coach/video/7123456789012345678")
  end

  # --- External / unknown ---

  test "unknown urls fall back to the external provider without an id" do
    analysis = VideoProviders.analyze("https://cdn.example.com/clip.mp4")
    assert_equal "external", analysis.provider_name
    assert_equal VideoProviders::External, analysis.provider_class
    assert_nil analysis.video_id
  end

  test "external provider never embeds and keeps the original url" do
    url = "https://cdn.example.com/clip.mp4"
    assert_not VideoProviders::External.can_embed?
    assert_equal url, VideoProviders::External.external_url(url)
    assert_nil VideoProviders::External.embed_url("whatever")
  end

  # --- Invalid input ---

  test "invalid urls return nil analysis" do
    assert_nil VideoProviders.analyze("not a url")
    assert_nil VideoProviders.analyze("javascript:alert(1)")
    assert_nil VideoProviders.analyze("ftp://example.com/clip.mp4")
    assert_nil VideoProviders.analyze("")
    assert_nil VideoProviders.analyze(nil)
  end

  test "unknown stored provider names fall back to external playback" do
    assert_equal VideoProviders::External, VideoProviders.for("mystery")
    assert_equal VideoProviders::YouTube, VideoProviders.for("youtube")
  end
end
