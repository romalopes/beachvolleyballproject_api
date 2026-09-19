module Api
  module V1
    # RESTful API for Training Sessions.
    #
    # Visibility and management are separate concerns:
    #   * index/show return only what the current user may see (drafts are
    #     private to coaches/curators/admins).
    #   * create/update/destroy require a training manager (coach, curator or
    #     admin). This is deliberately NOT based on `created_by_id`, because
    #     trainings are shared schedule resources.
    #
    # The creator is always derived from the authenticated request; a
    # `created_by_id` sent by the client is ignored.
    #
    # Serialization follows the existing project convention of Rails'
    # `render json:` with `only:`/`include:`. Drill data (description, visual
    # `definition` — which contains the steps — and skills) is read from the
    # Drill record and never copied into the training.
    class TrainingSessionsController < ApplicationController
      include ContentAuthorization

      CALENDAR_ATTRIBUTES = %i[id title starts_at ends_at location status created_by_id].freeze
      DETAIL_ATTRIBUTES = %i[id title description starts_at ends_at location status created_by_id
                             created_at updated_at].freeze
      FOCUS_ATTRIBUTES = %i[id skill_id custom_focus description position].freeze
      SESSION_DRILL_ATTRIBUTES = %i[id drill_id position duration_minutes notes].freeze

      before_action :set_training_session, only: %i[show update destroy]
      before_action :require_training_manager!, only: %i[create update destroy]
      before_action :validate_index_filters!, only: :index

      def index
        render json: filtered_training_sessions,
               only: CALENDAR_ATTRIBUTES,
               methods: %i[status_label duration_minutes],
               include: { created_by: { only: %i[id name] } }
      end

      def show
        render json: @training_session,
               only: DETAIL_ATTRIBUTES,
               methods: %i[status_label duration_minutes],
               include: detail_includes
      end

      def create
        @training_session = TrainingSession.new(training_session_params.merge(created_by: Current.user))
        persist
      end

      def update
        @training_session.assign_attributes(training_session_params)
        persist
      end

      def destroy
        @training_session.destroy
        head :no_content
      end

      private

      def persist
        if @training_session.save
          # Nested updates change positions; the associations preloaded in
          # set_training_session are stale after save, so re-read them in
          # their stored order.
          @training_session.reload
          render json: @training_session,
                 status: action_name == "create" ? :created : :ok,
                 only: DETAIL_ATTRIBUTES,
                 methods: %i[status_label duration_minutes],
                 include: detail_includes
        else
          render json: { errors: @training_session.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        render json: { errors: [ duplicate_reference_message(e) ] }, status: :unprocessable_entity
      rescue ActiveRecord::InvalidForeignKey
        render json: { errors: [ "The training references a skill or drill that does not exist" ] },
               status: :unprocessable_entity
      rescue ActiveRecord::CheckViolation
        # Database-level backstop; the model validations normally catch these.
        render json: { errors: [ "The training contains invalid focus or drill data" ] },
               status: :unprocessable_entity
      end

      def filtered_training_sessions
        scope = TrainingSession
                  .visible_to(Current.user)
                  .starting_between(params[:starts_at_from], params[:starts_at_to])
                  .includes(:created_by)
                  .ordered
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope
      end

      def set_training_session
        session = TrainingSession
                    .includes(:created_by, training_focuses: { skill: :category },
                              training_session_drills: { drill: { skills: :category } },
                              video_references: :video)
                    .find_by(id: params[:id])
        # A draft the user may not see is reported as not found rather than
        # forbidden, so the API never reveals that a draft exists.
        unless session && (session.publicly_visible? || Current.user&.content_manager?)
          return render json: { error: "Training Session not found" }, status: :not_found
        end

        @training_session = session
      end

      def detail_includes
        {
          created_by: { only: %i[id name] },
          training_focuses: {
            only: FOCUS_ATTRIBUTES,
            methods: %i[label],
            include: {
              skill: {
                only: %i[id title slug description],
                include: { category: { only: %i[id name slug] } }
              }
            }
          },
          training_session_drills: {
            only: SESSION_DRILL_ATTRIBUTES,
            include: {
              drill: {
                except: %i[created_by_id],
                include: {
                  skills: {
                    only: %i[id title slug],
                    include: { category: { only: %i[id name slug] } }
                  }
                }
              }
            }
          },
          video_references: {
            only: VideoReferencesController::REFERENCE_ONLY,
            methods: VideoReferencesController::REFERENCE_METHODS,
            include: { video: { only: VideoReferencesController::VIDEO_ONLY, methods: VideoReferencesController::VIDEO_METHODS } }
          }
        }
      end

      # Date/status filters are validated so bad input returns the standard
      # error shape instead of a database error.
      def validate_index_filters!
        errors = []
        errors << "starts_at_from is not a valid date" if invalid_date_param?(:starts_at_from)
        errors << "starts_at_to is not a valid date" if invalid_date_param?(:starts_at_to)
        if params[:status].present? && !TrainingSession::STATUSES.include?(params[:status])
          errors << "status is not included in the list"
        end

        render json: { errors: errors }, status: :unprocessable_entity if errors.any?
      end

      def invalid_date_param?(key)
        return false if params[key].blank?

        Time.zone.parse(params[key].to_s).nil?
      rescue ArgumentError
        true
      end

      def training_session_params
        permitted = params.require(:training_session).permit(
          :title, :description, :starts_at, :ends_at, :location, :status,
          training_focuses_attributes: %i[id skill_id custom_focus description position _destroy],
          training_session_drills_attributes: %i[id drill_id position duration_minutes notes _destroy]
        )

        fill_missing_positions!(permitted, :training_focuses_attributes)
        fill_missing_positions!(permitted, :training_session_drills_attributes)
        permitted
      end

      # The submitted array order is the intended order. Explicit positions are
      # honoured; rows that omit one fall back to their index so the final
      # order is always persisted.
      def fill_missing_positions!(permitted, key)
        rows = permitted[key]
        return if rows.blank?

        rows.each_with_index do |row, index|
          row["position"] = index if row["position"].blank?
        end
      end

      def duplicate_reference_message(error)
        case error.message
        when /index_training_session_drills_on_session_and_drill/
          "Drills must be unique within a training session"
        when /index_training_focuses_on_session_and_skill/
          "Skills must be unique within a training session"
        else
          "The training contains duplicate references"
        end
      end
    end
  end
end
