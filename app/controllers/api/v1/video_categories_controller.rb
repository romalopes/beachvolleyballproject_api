# Public video categories: list + show.
#
# Matches the existing Api::V1::CategoriesController pattern. `show` accepts
# either a numeric id or the slug so links stay readable.
module Api
  module V1
    class VideoCategoriesController < ApplicationController
      def index
        @categories = VideoCategory.ordered.includes(:videos)
        render json: @categories, methods: [:video_count]
      end

      def show
        @category = VideoCategory.includes(:videos)
                                 .find_by(slug: params[:id]) ||
                    VideoCategory.includes(:videos).find_by(id: params[:id])
        return render json: { error: "Video category not found" }, status: :not_found unless @category

        render json: @category, methods: [:video_count]
      end
    end
  end
end

