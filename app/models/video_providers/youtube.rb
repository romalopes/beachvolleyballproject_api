module VideoProviders
  # YouTube — fully embeddable with start/end timestamps and reliable
  # thumbnails. Accepts watch?v=, youtu.be/, /shorts/ and music.youtube.com
  # forms; the stored URL is normalized to the canonical watch form.
  class YouTube < Base
    HOSTS = %w[youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be].freeze

    def self.label
      "YouTube"
    end

    def self.provider_name
      "youtube"
    end

    def self.can_embed?
      true
    end

    def self.supports_start_timestamp?
      true
    end

    def self.supports_end_timestamp?
      true
    end

    def self.match?(url)
      HOSTS.include?(host(url))
    end

    def self.extract_id(url)
      if host(url) == "youtu.be"
        segments(url).first
      elsif (v = query_params(url)["v"]&.first)
        v
      else
        path = segments(url)
        shorts_index = path.index("shorts")
        shorts_index && path[shorts_index + 1]
      end
    end

    def self.normalized_url(url)
      id = extract_id(url)
      id ? "https://www.youtube.com/watch?v=#{id}" : url.to_s
    end

    def self.thumbnail_url(video_id)
      "https://i.ytimg.com/vi/#{video_id}/hqdefault.jpg" if video_id
    end

    # youtube-nocookie.com + start/end seconds; built only from the extracted
    # id, never from raw user input.
    def self.embed_url(video_id, start_seconds = nil, end_seconds = nil)
      return nil unless video_id

      params = {}
      params[:start] = start_seconds if start_seconds
      params[:end] = end_seconds if end_seconds
      query = params.any? ? "?#{URI.encode_www_form(params)}" : ""
      "https://www.youtube-nocookie.com/embed/#{video_id}#{query}"
    end
  end
end
