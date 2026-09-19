module VideoProviders
  # Vimeo — embeddable, but seeking is only supported via the player's start
  # fragment (`#t=`); there is no end-time support, so end timestamps are
  # intentionally declared unsupported and simply not applied.
  class Vimeo < Base
    def self.label
      "Vimeo"
    end

    def self.provider_name
      "vimeo"
    end

    def self.can_embed?
      true
    end

    def self.supports_start_timestamp?
      true
    end

    def self.supports_end_timestamp?
      false
    end

    def self.match?(url)
      host(url) == "vimeo.com"
    end

    def self.extract_id(url)
      segments(url).find { |segment| segment.match?(/\A\d+\z/) }
    end

    def self.normalized_url(url)
      id = extract_id(url)
      id ? "https://vimeo.com/#{id}" : url.to_s
    end

    def self.embed_url(video_id, start_seconds = nil, _end_seconds = nil)
      return nil unless video_id

      fragment = start_seconds ? "#t=#{format_timestamp(start_seconds)}" : ""
      "https://player.vimeo.com/video/#{video_id}#{fragment}"
    end

    def self.format_timestamp(seconds)
      minutes, remainder = seconds.divmod(60)
      "#{minutes}m#{remainder}s"
    end
  end
end
