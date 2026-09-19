module Api
  module V1
    # Public video library (index) plus standalone video creation (create):
    # a Video can exist without any reference — e.g. uploaded/entered \"for
    # later\" — and is attached to drills/skills/trainings afterwards through
    # the library picker on the reference forms.
    class VideosController < ApplicationController
      include ContentAuthorization

      before_action :require_content_creator!, only: :create
      before_action :set_video, only: [:show, :update, :destroy]

      VIDEO_ONLY = %i[id title description provider source_url thumbnail_url
                      duration_seconds created_by_id].freeze
      VIDEO_METHODS = %i[provider_label can_embed embed_url external_url
                         reference_count].freeze
      # Categories and tags are associations, not methods, so they are
      # serialized through include: with an explicit field allowlist.
      VIDEO_INCLUDE = {
        video_category: { only: %i[id name slug description position] },
        video_tags: { only: %i[id name] },
      }.freeze

      def index
        @videos = Video.includes(:video_references, :video_category, :video_tags)
                       .left_joins(:video_category)
                       .order(Arel.sql("video_categories.position ASC NULLS LAST"), :title)
        render json: @videos, only: VIDEO_ONLY, methods: VIDEO_METHODS, include: VIDEO_INCLUDE
      end

      def show
        render json: @video, only: VIDEO_ONLY, methods: VIDEO_METHODS, include: VIDEO_INCLUDE
      end

      def create
        attrs = video_params.to_h
        @video = Video.find_or_create_from_url!(
          attrs["source_url"],
          attrs.slice("title", "description", "video_category_id")
               .merge(created_by: Current.user),
        )
        unless @video
          return render json: { errors: ["Source URL is not a valid video link"] },
                        status: :unprocessable_entity
        end
        sync_tags
        render_video(status: @video.previously_new_record? ? :created : :ok)
      end

      def update
        authorize_content_owner!(@video.created_by)
        if @video.update(video_params)
          sync_tags
          render_video(status: :ok)
        else
          render json: { errors: @video.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_content_owner!(@video.created_by)
        @video.destroy
        head :no_content
      end

      private

      def set_video
        @video = Video.includes(:video_category, :video_tags).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Video not found" }, status: :not_found
      end

      # video_tag_ids is an association, not a column, so it is kept out of the
      # attribute hash update() would reject as unknown.
      def video_params
        params.require(:video).permit(:source_url, :title, :description, :video_category_id)
      end

      # Tags are replaced wholesale when the key is present: an explicit empty
      # array clears every tag, while an absent key leaves them untouched.
      def sync_tags
        ids = params.require(:video)[:video_tag_ids]
        return if ids.nil?

        @video.video_tags = VideoTag.where(id: Array(ids).map(&:to_i))
      end

      def render_video(status:)
        @video.reload
        render json: @video, status: status, only: VIDEO_ONLY, methods: VIDEO_METHODS,
                             include: VIDEO_INCLUDE
      end
    end
  end
end
