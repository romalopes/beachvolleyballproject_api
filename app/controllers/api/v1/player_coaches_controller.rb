module Api
  module V1
    # Who coaches whom: the ongoing coaching relationship between a coach profile
    # and a player profile.
    #
    # This is deliberately *not* the assessment permission. A coach may assess any
    # player the existing assessment rules allow, with or without a relationship
    # here — `PlayerCoach` answers "is this person coaching this player?", which is
    # a question about the roster, not about authority to record an opinion. The
    # distinction is the whole point of the model: a relationship that ended must
    # never retract a rating recorded while it ran.
    #
    # Lifecycle: a relationship is created with a `start_date` and retired by
    # setting an `end_date`. There is no `destroy` — the row is the context that
    # makes a historical assessment explicable. A relationship that resumes is a
    # NEW row, so the earlier period keeps its own dates.
    #
    # Authority: reads need a training manager (the payload names people); writes
    # need a content creator, and a coach may only record *their own* coaching —
    # oversight (curator/admin) may record any, which is what lets a club clean up
    # records kept by a coach who has since left.
    class PlayerCoachesController < ApplicationController
      include ContentAuthorization

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: %i[create update end_relationship]
      before_action :validate_filters!, only: :index
      before_action :set_relationship, only: %i[show update end_relationship]

      # `end` is a Ruby keyword, so the action (and the route) is `end_relationship`.
      # Modelled on `end_member` in OrganisationsController, which had the same
      # problem.

      def index
        relationships = visible_relationships(
          PlayerCoach.includes(player_profile: :person, coach_profile: :person).ordered
        )

        if (player_id = params[:player_profile_id].presence)
          relationships = relationships.for_player(player_id.to_i)
        end
        if (coach_id = params[:coach_profile_id].presence)
          relationships = relationships.for_coach(coach_id.to_i)
        end

        relationships = apply_status_filter(relationships)
        # `apply_status_filter` renders on an unknown value; without this the
        # action would carry on and map over nil.
        return if relationships.nil?

        # No pagination: a person has a handful of coaches or players, and the
        # caller always narrows by one of the two ids. The pagination envelope
        # would add a page nobody can ask for.
        render json: { data: relationships.map(&:metadata) }
      end

      def show
        render json: @relationship.metadata
      end

      # Recording a coaching relationship. Either profile may be accountless — a
      # coach who never signed up can coach a player who never signed up, which is
      # the ordinary case for a club's juniors.
      def create
        player_profile = PlayerProfile.find_by(id: relationship_params[:player_profile_id])
        coach_profile = CoachProfile.find_by(id: relationship_params[:coach_profile_id])

        return render json: { errors: [ "Player not found" ] }, status: :not_found if player_profile.nil?
        return render json: { errors: [ "Coach not found" ] }, status: :not_found if coach_profile.nil?
        return unless authorize_coach_of_record!(coach_profile)

        # Already coaching: report the row that exists rather than creating a
        # second open period. 409 rather than 422 because the request was
        # well-formed — the state is what conflicts (the same answer
        # OrganisationsController#create_member gives).
        existing = PlayerCoach.current_period_for(player_profile, coach_profile)
        if existing
          return render json: {
            error: "#{coach_profile.full_name} is already coaching #{player_profile.full_name}",
            player_coach: existing.metadata
          }, status: :conflict
        end

        relationship = PlayerCoach.new(
          player_profile: player_profile,
          coach_profile: coach_profile,
          start_date: relationship_params[:start_date].presence || Date.current
        )

        if relationship.save
          render json: relationship.metadata, status: :created
        else
          render json: { errors: relationship.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Correct a period. The two profiles are deliberately not updatable: moving a
      # relationship to another player or coach would silently rewrite history, so
      # that is a new relationship instead.
      def update
        return unless authorize_relationship_manager!(@relationship)

        if @relationship.update(relationship_update_params)
          render json: @relationship.metadata
        else
          render json: { errors: @relationship.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Ending a relationship. An update, never a delete: assessments recorded
      # during it keep the context that explains them.
      def end_relationship
        return unless authorize_relationship_manager!(@relationship)

        if @relationship.ended?
          return render json: {
            error: "This coaching relationship already ended on #{@relationship.end_date.iso8601}",
            player_coach: @relationship.metadata
          }, status: :conflict
        end

        end_date = ending_date
        if end_date.nil?
          return render json: { errors: [ "end_date is not a valid date" ] },
                        status: :unprocessable_entity
        end

        if @relationship.update(end_date: end_date)
          render json: @relationship.metadata
        else
          render json: { errors: @relationship.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      private

      # "Which of these relationships may this caller see?" — the same soft
      # visibility the player and coach catalogues use, applied to both ends. A
      # coach's private player must not become visible merely because a roster row
      # names them, or the list would contradict the profile it points at.
      def visible_relationships(scope)
        user = Current.user
        return scope if user.nil? || user.admin? || user.curator?

        scope
          .where(player_profile_id: PlayerProfile.visible_to(user).select(:id))
          .where(coach_profile_id: CoachProfile.visible_to(user).select(:id))
      end

      # A relationship has no status column, so "current" is the absence of an end
      # date and "historical" is its presence. An unknown value is rejected rather
      # than silently returning everything.
      def apply_status_filter(scope)
        case params[:status].presence
        when nil, "all" then scope
        when "current" then scope.current
        when "historical" then scope.historical
        else
          render json: { errors: [ "status is not included in the list" ] },
                 status: :unprocessable_entity
          nil
        end
      end

      def validate_filters!
        %i[player_profile_id coach_profile_id].each do |key|
          next if params[key].blank?
          next if params[key].to_s.match?(/\A[1-9]\d*\z/)

          render json: { errors: [ "#{key} must be a positive integer" ] },
                 status: :unprocessable_entity
          return
        end
      end

      def set_relationship
        @relationship = PlayerCoach.includes(player_profile: :person, coach_profile: :person)
                                   .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Coaching relationship not found" }, status: :not_found
      end

      # A coach records their own coaching. Oversight records any, which is what
      # lets a club finish a roster the coach of record never completed.
      def authorize_coach_of_record!(coach_profile)
        return true if oversight_or_coach_of_record?(coach_profile)

        render json: {
          error: "A coach may only record their own coaching relationships"
        }, status: :forbidden
        false
      end

      # The same rule for a row that already exists: the coach of record, their
      # account, oversight — or nobody.
      def authorize_relationship_manager!(relationship)
        authorize_coach_of_record!(relationship.coach_profile)
      end

      # Today unless the caller names a day. Parsed explicitly rather than handed
      # to ActiveRecord: Rails would turn an unparseable string into nil, and nil
      # is exactly the value that means "still coaching", so a typo would silently
      # reopen the relationship instead of being refused.
      def ending_date
        raw = params.dig(:player_coach, :end_date).presence
        return Date.current if raw.blank?

        Date.parse(raw.to_s)
      rescue Date::Error, TypeError
        nil
      end

      def relationship_params
        params.require(:player_coach)
              .permit(:player_profile_id, :coach_profile_id, :start_date)
              .to_h
              .symbolize_keys
      end

      # `end_date` is permitted so a period can also be closed by an ordinary
      # update; it may never be *cleared*, which the model refuses.
      def relationship_update_params
        params.require(:player_coach)
              .permit(:start_date, :end_date)
              .to_h
              .symbolize_keys
      end
    end
  end
end
