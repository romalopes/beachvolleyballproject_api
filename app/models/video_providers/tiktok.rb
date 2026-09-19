module VideoProviders
  # TikTok — the numeric video id is extracted, but TikTok restricts embedding
  # and has no timestamp seeking, so playback always falls back to "Watch on
  # TikTok".
  class TikTok < Base
    def self.label
      "TikTok"
    end

    def self.provider_name
      "tiktok"
    end

    def self.match?(url)
      host(url).to_s.end_with?("tiktok.com")
    end

    def self.extract_id(url)
      path = segments(url)
      video_index = path.index("video")
      id = video_index && path[video_index + 1]
      id if id&.match?(/\A\d+\z/)
    end

    # Normalized form keeps the canonical path and drops tracking params.
    def self.normalized_url(url)
      uri = URI.parse(url.to_s)
      uri.query = nil
      uri.fragment = nil
      uri.to_s
    rescue URI::Error
      url.to_s
    end
  end
end
