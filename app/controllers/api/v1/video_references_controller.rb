module Api
  module V1
    # Nested CRUD for VideoReference rows: /api/v1/drills/:drill_id/video_references
    # and /api/v1/skills/:skill_id/video_references.
    #
    # The reference target comes from the URL, never from params, so a client
    # cannot attach a reference to an arbitrary type. The Video itself is
    # either reused (same normalized provider/id) or created from the given
    # source_url; a reference is never the owner of the Video, so deletion
    # removes only the association.
    class VideoReferencesController < ApplicationController
      include ContentAuthorization

      before_action :set_referenceable
      before_action :require_content_creator!, only: :create
      before_action :set_video_reference, only: %i[update destroy]
      # A render inside a before_action halts the chain; authorizing here keeps
      # update/destroy free of double-render paths.
      before_action :authorize_reference_owner!, only: %i[update destroy]

      REFERENCE_ONLY = %i[id start_seconds end_seconds title description position].freeze
      REFERENCE_METHODS = %i[can_embed embed_url external_url].freeze
      VIDEO_ONLY = %i[id title provider source_url thumbnail_url duration_seconds].freeze
      VIDEO_METHODS = %i[provider_label].freeze

      def create
        video = resolve_video
        unless video
          return render json: { errors: ["Video URL is not a valid video link"] },
                        status: :unprocessable_entity
        end

        @video_reference = @referenceable.video_references
                                         .new(reference_params.merge(video: video))
        if @video_reference.save
          render_reference(status: :created)
        else
          render json: { errors: @video_reference.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        if @video_reference.update(reference_params)
          render_reference
        else
          render json: { errors: @video_reference.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        @video_reference.destroy
        head :no_content
      end

      private

      def set_referenceable
        @referenceable =
          if params[:drill_id]
            Drill.find_by(id: params[:drill_id])
          elsif params[:skill_id]
            Skill.find_by(id: params[:skill_id])
          elsif params[:training_session_id]
            TrainingSession.find_by(id: params[:training_session_id])
          end
        return if @referenceable

        render json: { error: "#{referenceable_label} not found" }, status: :not_found
      end

      def referenceable_label
        if params[:drill_id]
          "Drill"
        elsif params[:skill_id]
          "Skill"
        else
          "Training Session"
        end
      end

      def set_video_reference
        @video_reference = @referenceable.video_references.find_by(id: params[:id])
        return if @video_reference

        render json: { error: "Video reference not found" }, status: :not_found
      end

      def authorize_reference_owner!
        authorize_content_owner!(@video_reference.video.created_by)
      end

      # Reuse-or-create: an existing Video with the same normalized provider
      # identity is reused so the same clip is never duplicated.
      def resolve_video
        if (video_id = params.dig(:video_reference, :video_id)).present?
          return Video.find_by(id: video_id)
        end

        video_params = params.dig(:video_reference, :video) || {}
        return nil if video_params[:source_url].blank?

        Video.find_or_create_from_url!(
          video_params[:source_url],
          video_params.permit(:title, :description).to_h,
        )
      end

      def reference_params
        params.require(:video_reference)
              .permit(:start_seconds, :end_seconds, :title, :description, :position,
                      :video_id, video: %i[source_url title description])
              .except(:video_id, :video)
      end

      def render_reference(status: :ok)
        render json: @video_reference,
               status: status,
               only: REFERENCE_ONLY,
               methods: REFERENCE_METHODS,
               include: { video: { only: VIDEO_ONLY, methods: VIDEO_METHODS } }
      end
    end
  end
end
