module VideoProviders
  # Instagram — posting code is extracted, but Instagram restricts embedding
  # and offers no seeking, so playback always falls back to "Watch on
  # Instagram" with the stored (or provider) thumbnail.
  class Instagram < Base
    def self.label
      "Instagram"
    end

    def self.provider_name
      "instagram"
    end

    def self.match?(url)
      %w[instagram.com www.instagram.com].include?(host(url))
    end

    # Shortcode for /p/, /reel/, /reels/ and /tv/ links.
    def self.extract_id(url)
      path = segments(url)
      index = path.index { |segment| %w[p reel reels tv].include?(segment) }
      index && path[index + 1]
    end

    # Normalized form keeps the post path and drops tracking query params.
    def self.normalized_url(url)
      uri = URI.parse(url.to_s)
      uri.host = "www.instagram.com"
      uri.query = nil
      uri.fragment = nil
      uri.to_s
    rescue URI::Error
      url.to_s
    end
  end
end
