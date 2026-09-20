# Admin video category management: index/create/update/destroy.
#
# Only administrators can mutate categories. Deleting a category
# nullifies video_category_id on its videos rather than deleting them.
module Api
  module V1
    module Admin
      class VideoCategoriesController < ApplicationController
        include RequestLogging
        include Reorderable
        before_action :authorize_admin!

        def index
          @categories = VideoCategory.ordered.includes(:videos)
          render json: @categories, methods: [:video_count]
        end

        def create
          @category = VideoCategory.new(category_params)
          @category.created_by = Current.user
          if @category.save
            render json: @category, status: :created
          else
            render json: { errors: @category.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        def update
          @category = VideoCategory.find(params[:id])
          if @category.update(category_params)
            render json: @category
          else
            render json: { errors: @category.errors.full_messages },
                   status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Video category not found" }, status: :not_found
        end

        def destroy
          @category = VideoCategory.find(params[:id])
          @category.videos.update_all(video_category_id: nil)
          @category.destroy
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Video category not found" }, status: :not_found
        end

        # Drag-and-drop ordering for the settings page: the client sends the
        # complete ordered id list and every position becomes its index.
        def reorder
          return unless reorder_records(VideoCategory)

          render json: VideoCategory.ordered.includes(:videos), methods: [:video_count]
        end

        private

        def category_params
          # `position` is intentionally excluded: order is managed by
          # drag-and-drop (see #reorder), which keeps positions dense and
          # duplicate-free. New categories are appended by the model.
          params.require(:video_category).permit(:name, :description)
        end
      end
    end
  end
end
