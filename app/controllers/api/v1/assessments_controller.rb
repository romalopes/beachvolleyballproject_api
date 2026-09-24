module Api
  module V1
    # RESTful API for Assessments: a coach's rating of a player against a category.
    #
    # Existence and authority are separate concerns (see Assessment):
    #   * index/show return only rows that exist for the caller — `active` rows
    #     on players they may see, plus any row they are a stakeholder of
    #     (recorder or attributed coach), plus everything for curators/admins.
    #     There is deliberately no `include_private`: visibility is not a switch.
    #   * create requires a content creator (coach/admin). A coach may only
    #     attribute a row to themselves — `coach_profile_id` either names their
    #     own CoachProfile or is omitted, in which case it is resolved from the
    #     request. Only a curator/admin may record on behalf of another coach.
    #   * update requires a stakeholder or a curator/admin. Re-pointing a row at
    #     another player is a merge, not an edit, and is refused with 422.
    #
    # There is no destroy: nothing in this project is ever hard-deleted, and a
    # withdrawn assessment carries information ("this rating was retracted")
    # that a deleted one would silently lose.
    #
    # The rating conversion lives in one place: requests carry the coach's own
    # entry (`value` + `scale`), and the server derives the canonical `score`
    # through RatingScale. A canonical `score` may be sent directly instead —
    # for clients that already converted — in which case `scale` describes how
    # to display it and `reported_value` how it was entered.
    class AssessmentsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: :create
      before_action :set_assessment, only: %i[show update]
      before_action :validate_index_filters!, only: :index

      # Serializable output. The canonical `score` plus the coach's own
      # `reported_value`/`scale` keep every row auditable; `ten_scale` and
      # `five_scale` let the SPA show the rating on either scale without
      # converting it again.
      ASSESSMENT_ONLY = %i[
        id player_profile_id coach_profile_id category_id custom_category
        training_session_id score reported_value scale notes status
        created_at updated_at
      ].freeze
      ASSESSMENT_METHODS = %i[
        category_label ten_scale five_scale score_label status_label
        player_profile_id coach_profile_id
      ].freeze
      ASSESSMENT_INCLUDES = {
        created_by: { only: %i[id name] },
        category: { only: %i[id name slug] }
      }.freeze

      def index
        rows = Assessment
                 .visible_to(Current.user)
                 .ordered
                 .includes(:player_profile, :coach_profile, :created_by, :category)
        rows = rows.where(player_profile_id: params[:player_id]) if params[:player_id].present?
        rows = rows.where(coach_profile_id: params[:coach_id]) if params[:coach_id].present?
        rows = rows.where(category_id: params[:category_id]) if params[:category_id].present?
        rows = rows.where(training_session_id: params[:training_session_id]) if params[:training_session_id].present?
        rows = params[:status].present? ? rows.where(status: params[:status]) : rows.active
        if params[:mine].present?
          rows = rows.where(created_by_id: Current.user.id)
                     .or(rows.where(coach_profile_id: Current.user.person&.coach_profile&.id))
        end

        records, meta = paginate(rows)

        render json: {
          data: records.map { |row| serialize(row) },
          meta: meta
        }
      end

      # Soft visibility: a row the caller may not see is 404, not 403 (the same
      # as not existing, so the listing and the detail can never disagree).
      def show
        if @assessment.visible_to_user?(Current.user)
          render json: serialize(@assessment)
        else
          render json: { error: "Assessment not found" }, status: :not_found
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Assessment not found" }, status: :not_found
      end

      # The assessor is whoever the coach says it is: their own CoachProfile
      # when omitted or named explicitly, or — curator/admin only — another
      # coach's. Provenance (`created_by`) is always stamped from the request.
      def create
        @assessment = Assessment.new(assessment_params.except(:value))
        @assessment.created_by = Current.user
        resolve_assessor!
        return if performed?

        apply_value!
        return if performed?

        resolve_score!
        return if performed?

        if @assessment.save
          render json: serialize(@assessment), status: :created
        else
          render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Edit a rating, publish a draft or withdraw a row. Only a stakeholder
      # (recorder or attributed coach) or a curator/admin may. Re-pointing the
      # row at another player is a merge, not an edit.
      def update
        unless @assessment.manageable_by?(Current.user)
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        if repointing_player?
          return render json: { errors: [ "This assessment already belongs to a player; changing it is a merge, not an edit." ] },
                        status: :unprocessable_entity
        end

        @assessment.assign_attributes(assessment_params.except(:value))
        apply_value!
        return if performed?

        resolve_score!
        return if performed?

        if @assessment.save
          render json: serialize(@assessment)
        else
          render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_assessment
        @assessment = Assessment
                        .includes(:player_profile, :coach_profile, :created_by, :category)
                        .find(params[:id])
      end

      def assessment_params
        params.require(:assessment).permit(
          :player_profile_id, :coach_profile_id, :category_id, :custom_category,
          :training_session_id, :score, :reported_value, :scale, :value,
          :notes, :status
        )
      end

      # A coach speaks for themselves; only oversight speaks for another coach.
      # When nobody is named, the row is still attributed — to the caller.
      def resolve_assessor!
        requested = assessment_params[:coach_profile_id].presence&.to_i

        if requested.nil?
          own = Current.user.person&.coach_profile
          if own.nil?
            @assessment.errors.add(:coach_profile, "could not be determined from the signed-in account")
            render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
          else
            @assessment.coach_profile = own
          end
          return
        end

        @assessment.coach_profile = CoachProfile.find_by(id: requested)
        if @assessment.coach_profile.nil?
          render json: { errors: [ "Coach profile not found" ] }, status: :unprocessable_entity
          return
        end

        return if Assessment.oversight?(Current.user)
        return if Current.user.person&.coach_profile&.id == requested

        render json: { errors: [ "You may only record assessments as yourself" ] }, status: :forbidden
      end

      # `value` is the coach's own entry; unlike the model's forgiving setter,
      # an entry that does not exist on the named scale — or is not a number —
      # is an error the caller can act on, not a row saved without a rating.
      def apply_value!
        return if assessment_params[:value].blank?

        scale = assessment_params[:scale].presence || @assessment.scale || RatingScale::DEFAULT_SCALE
        entry = assessment_params[:value].to_s
        number = Integer(entry, exception: false)
        unless RatingScale.legal_value?(number, scale: scale)
          @assessment.errors.add(
            :value,
            number.nil? ? "must be a number" : "is not a value on the #{scale} scale"
          )
          return render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
        end

        @assessment.scale = scale
        @assessment.reported_value = number
        @assessment.score = RatingScale.to_score(number, scale: scale)
      end

      # `score` given directly still records how it was entered: the band's
      # representative value beside it, unless the caller already said.
      #
      # Requests that carry neither entry are publishes and status flips: a
      # draft becoming `active` must already hold a rating (the model refuses
      # to publish an unrated row), which is why this method renders nothing
      # on that path — the save below reports it.
      def resolve_score!
        return if assessment_params[:value].present?
        return if assessment_params[:score].blank? && assessment_params[:reported_value].blank?

        scale = assessment_params[:scale].presence || @assessment.scale || RatingScale::DEFAULT_SCALE

        if assessment_params[:score].present?
          score = assessment_params[:score].to_i
          unless score.between?(RatingScale::SCORE_MIN, RatingScale::SCORE_MAX)
            @assessment.errors.add(:score, "must be between 0 and 100")
            return render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
          end

          @assessment.scale = scale
          @assessment.score = score
          @assessment.reported_value ||= RatingScale.reported_for(score, scale: scale)
        else
          entry = assessment_params[:reported_value]
          value = entry.to_i
          unless RatingScale.legal_value?(value, scale: scale)
            @assessment.errors.add(
              :reported_value,
              value.to_s == entry.to_s ? "is not a value on the #{scale} scale" : "must be a number"
            )
            return render json: { errors: @assessment.errors.full_messages }, status: :unprocessable_entity
          end

          @assessment.scale = scale
          @assessment.reported_value = value
          @assessment.score = RatingScale.to_score(value, scale: scale)
        end
      end

      def repointing_player?
        requested = assessment_params[:player_profile_id].presence
        requested.present? && requested.to_i != @assessment.player_profile_id
      end

      # The listing only narrows to published club knowledge by default; an
      # explicit status filter replaces that default, so drafts and withdrawn
      # rows are reachable to those who may see them.
      def validate_index_filters!
        return if params[:status].blank? || Assessment::STATUSES.include?(params[:status])

        render json: { errors: [ "status is not included in the list" ] }, status: :unprocessable_entity
      end

      def serialize(row)
        payload = row.as_json(
          only: ASSESSMENT_ONLY,
          methods: ASSESSMENT_METHODS,
          include: ASSESSMENT_INCLUDES
        )
        # `as_json(include:)` drops a nil `belongs_to`, but the SPA relies on
        # the key always being present (nil = recorded before provenance).
        payload["created_by"] = nil unless payload.key?("created_by")
        payload["category"] = nil unless payload.key?("category")
        payload
      end
    end
  end
end
