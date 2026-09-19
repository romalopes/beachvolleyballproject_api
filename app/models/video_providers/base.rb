module VideoProviders
  # Contract shared by every provider. All methods are class methods so no
  # instantiation is needed; a provider only overrides what differs from the
  # safe default (no embedding, URL passthrough).
  class Base
    # Human-readable provider name shown in the UI ("Watch on YouTube").
    def self.label
      "External video"
    end

    # Stored value for Video#provider.
    def self.provider_name
      "external"
    end

    # --- Capabilities (never assume a URL is embeddable) ---

    def self.can_embed?
      false
    end

    def self.supports_start_timestamp?
      false
    end

    def self.supports_end_timestamp?
      false
    end

    # --- URL handling ---

    def self.match?(_url)
      false
    end

    def self.extract_id(_url)
      nil
    end

    # Canonical URL to store on the Video record.
    def self.normalized_url(url)
      url.to_s
    end

    # Link used by "Watch on [Provider]" — defaults to the stored URL.
    def self.external_url(url)
      normalized_url(url)
    end

    # --- Playback ---

    def self.thumbnail_url(_video_id)
      nil
    end

    # Embeddable player URL built ONLY from the provider's own allowlisted
    # host plus the extracted id; user input never becomes an iframe src.
    def self.embed_url(_video_id, _start_seconds = nil, _end_seconds = nil)
      nil
    end

    # --- Parsing helpers ---

    def self.host(url)
      URI.parse(url.to_s).host&.downcase
    rescue URI::Error
      nil
    end

    def self.segments(url)
      URI.parse(url.to_s).path.split("/").compact_blank
    rescue URI::Error
      []
    end

    def self.query_params(url)
      query = URI.parse(url.to_s).query
      return {} if query.blank?

      # URI.decode_www_form (not CGI.parse, whose load state varies between
      # the test suite and a running server).
      URI.decode_www_form(query).to_h { |key, value| [ key, [ value ] ] }
    rescue URI::Error
      {}
    end
  end
end
