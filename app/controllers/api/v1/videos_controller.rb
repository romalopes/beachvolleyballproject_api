module Api
  module V1
    # Public list of the reusable videos with where they are used. The
    # lightweight index backs the /videos SPA page and the API health check.
    class VideosController < ApplicationController
      def index
        @videos = Video.includes(:video_references).order(:title)
        render json: @videos,
               only: %i[id title provider source_url thumbnail_url duration_seconds],
               methods: %i[provider_label can_embed external_url reference_count]
      end
    end
  end
end
