module VideoProviders
  # External — the catch-all for any other valid http(s) URL. Embedding is
  # disabled (an arbitrary URL must never become an iframe source) and
  # playback is a plain "Watch" link to the original URL.
  class External < Base
    def self.label
      "External"
    end

    def self.provider_name
      "external"
    end

    def self.match?(url)
      uri = URI.parse(url.to_s)
      %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
    rescue URI::Error
      false
    end
  end
end
