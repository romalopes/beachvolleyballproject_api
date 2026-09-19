# VideoProviders — the provider abstraction for external videos.
#
# Every concrete provider (YouTube, Vimeo, …) is a class extending
# VideoProviders::Base and declaring its capabilities as class methods. The
# registry below is the only place that knows the concrete list; neither the
# controllers nor the React app need provider-specific logic — they consume the
# normalized fields rendered by the API (can_embed / embed_url / external_url).
#
# Adding a provider = one new file in app/models/video_providers plus a line
# in `registry`. See README.md ("Videos & VideoReferences").
module VideoProviders
  # The normalized outcome of parsing a URL: which provider it belongs to, the
  # provider-specific video id (nil when the provider has none) and the
  # canonical URL to store.
  Analysis = Struct.new(:provider_class, :provider_name, :video_id, :normalized_url, keyword_init: true)

  # Specific providers first; External must stay last (it matches any valid
  # http(s) URL). Resolved lazily so the constants autoload cleanly.
  def self.registry
    [ YouTube, Vimeo, Instagram, TikTok, External ]
  end

  # Parses a URL into an Analysis, or returns nil when the URL is not a usable
  # http(s) video link. Never raises.
  def self.analyze(url)
    string = url.to_s.strip
    return nil unless string.match?(%r{\Ahttps?://}i)

    registry.each do |provider|
      next unless provider.match?(string)

      return Analysis.new(
        provider_class: provider,
        provider_name: provider.provider_name,
        video_id: provider.extract_id(string).presence,
        normalized_url: provider.normalized_url(string)
      )
    end
    nil
  rescue URI::Error
    nil
  end

  # Resolves the provider class stored on a Video record. Unknown provider
  # names fall back to External so playback degrades to a watch link instead
  # of raising.
  def self.for(provider_name)
    registry.find { |provider| provider.provider_name == provider_name } || External
  end
end
