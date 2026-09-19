module Api
  module V1
    # Public video library (index) plus standalone video creation (create):
    # a Video can exist without any reference — e.g. uploaded/entered "for
    # later" — and is attached to drills/skills/trainings afterwards through
    # the library picker on the reference forms.
    class VideosController < ApplicationController
      include ContentAuthorization

      before_action :require_content_creator!, only: :create

      VIDEO_ONLY = %i[id title provider source_url thumbnail_url duration_seconds].freeze
      VIDEO_METHODS = %i[provider_label can_embed embed_url external_url reference_count].freeze

      def index
        @videos = Video.includes(:video_references).order(:title)
        render json: @videos, only: VIDEO_ONLY, methods: VIDEO_METHODS
      end

      def create
        attrs = video_params.to_h
        @video = Video.find_or_create_from_url!(
          attrs["source_url"],
          attrs.slice("title", "description"),
        )
        unless @video
          return render json: { errors: ["Source URL is not a valid video link"] },
                        status: :unprocessable_entity
        end

        render_video(status: @video.previously_new_record? ? :created : :ok)
      end

      private

      def video_params
        params.require(:video).permit(:source_url, :title, :description)
      end

      def render_video(status:)
        render json: @video, status: status, only: VIDEO_ONLY, methods: VIDEO_METHODS
      end
    end
  end
end
