# Admin video tag management: create/update/destroy.
#
# Only administrators can mutate tags. Deleting a tag removes its taggings
# (and therefore its use on videos) but never touches the videos themselves.
module Api
  module V1
    module Admin
      class VideoTagsController < ApplicationController
        include RequestLogging
        before_action :authorize_admin!

        def index
          # left_joins (not joins) keeps tags with zero videos in the list, so
          # the management page can show and delete unused tags. The count is
          # attached as a `video_count` attribute for the JSON serializer.
          @tags = VideoTag.left_joins(:video_taggings)
                          .group(:id)
                          .order(:name)
                          .select("video_tags.*, COUNT(video_taggings.id) AS video_count")
          render json: @tags, methods: [:video_count]
        end

        def create
          @tag = VideoTag.new(tag_params)
          if @tag.save
            render json: @tag, status: :created
          else
            render json: { errors: @tag.errors.full_messages },
                   status: :unprocessable_entity
          end
        end

        def update
          @tag = VideoTag.find(params[:id])
          if @tag.update(tag_params)
            render json: @tag
          else
            render json: { errors: @tag.errors.full_messages },
                   status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Video tag not found" }, status: :not_found
        end

        def destroy
          @tag = VideoTag.find(params[:id])
          @tag.destroy
          head :no_content
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Video tag not found" }, status: :not_found
        end

        private

        def tag_params
          params.require(:video_tag).permit(:name)
        end
      end
    end
  end
end
