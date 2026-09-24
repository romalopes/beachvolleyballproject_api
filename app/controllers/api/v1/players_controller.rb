module Api
  module V1
    # Players are PlayerProfile records joined to their Person identity.
    #
    # Read access is limited to training managers (coach/curator/admin): the
    # payload carries contact details and coach observations. Creating a player
    # additionally requires a content creator (coach/admin). A player with no
    # account can be recorded by staff and used immediately — no Account is
    # created (see PersonCreationService).
    class PlayersController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: %i[create update]
      before_action :set_player, only: %i[show update]
      before_action :validate_status_filter!, only: :index

      # Permitted input.
      PERSON_ATTRS = %i[first_name last_name email phone date_of_birth].freeze
      PROFILE_ATTRS = %i[preferred_position level status visibility].freeze

      # Serializable output.
      PROFILE_ONLY = %i[id person_id preferred_position level status visibility created_at updated_at].freeze
      PERSON_ONLY = %i[id first_name last_name email phone date_of_birth creation_source].freeze
      PROFILE_METHODS = %i[full_name account_status player_profile_id].freeze
      DETAIL_METHODS = PROFILE_METHODS + %i[training_session_count]

      def index
        # Archived players are hidden from the catalogue by default (they are no
        # longer schedulable) but stay reachable with `?status=archived`, which
        # is how the SPA offers "show archived" and "restore".
        #
        # Visibility is the soft variant: other coaches' private players are
        # hidden from the listing, but the training form's picker must still
        # see everyone (`?include_private=1`) because visibility never blocks
        # scheduling. `?mine=1` narrows to the players this user recorded.
        players = profile_scope
                  .includes(:person, :created_by)
                  .joins(:person)
                  .order(people: { last_name: :asc, first_name: :asc }, player_profiles: { id: :asc })

        if params[:q].present?
          term = "%#{params[:q]}%"
          players = players.where("people.last_name ILIKE :t OR people.first_name ILIKE :t OR people.email ILIKE :t",
                                  t: term)
        end
        if params[:email].present?
          players = players.where(people: { email: params[:email] })
        end
        unless params[:include_private].present?
          players = players.visible_to(Current.user)
        end
        if params[:mine].present?
          players = players.owned_by(Current.user)
        end

        records, meta = paginate(players)

        render json: {
          data: records.map { |profile| serialize(profile) },
          meta: meta
        }
      end

      # Soft visibility: a private player is 404 to a coach who neither owns
      # them nor is a curator/admin (the same as not existing, so the catalogue
      # and the detail can never disagree).
      def show
        unless @player.visible_to_user?(Current.user)
          return render json: { error: "Player not found" }, status: :not_found
        end

        payload = @player.as_json(
          only: PROFILE_ONLY,
          include: {
            person: { only: PERSON_ONLY },
            created_by: { only: %i[id name] },
            training_session_participants: {
              only: %i[id status notes created_at],
              include: {
                training_session: { only: %i[id title starts_at ends_at location status visibility] }
              }
            }
          },
          methods: DETAIL_METHODS
        )
        # `as_json(include:)` drops a nil `belongs_to`, but the SPA relies on
        # the key always being present (nil = recorded before Phase C).
        payload["created_by"] = nil unless payload.key?("created_by")

        # Coaching history (plan 4.2): the count is published rows only, and
        # the history is whatever exists for this caller — drafts and
        # withdrawn rows reach their stakeholders through Assessment.visible_to
        # and never leak to anybody else.
        payload["assessment_count"] = @player.active_assessment_count
        payload["assessments"] = Assessment.visible_to(Current.user)
                                         .where(player_profile_id: @player.id)
                                         .ordered
                                         .includes(:category, :created_by, :coach_profile)
                                         .map(&:metadata)

        render json: payload
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Player not found" }, status: :not_found
      end

      # A player recorded through the API is a person a coach entered (not a
      # self-signup): PersonCreationService stamps the provenance and the author
      # so identity resolution can tell the two apart. The response carries
      # `possible_duplicates` — suggestions only, never an automatic merge.
      #
      # Two ways to name the player: `person_id` links a PlayerProfile to a
      # person that already exists (found through /api/v1/people), while nested
      # `person` attributes record a new one.
      def create
        profile = PlayerProfile.new(player_params)
        profile.created_by ||= Current.user
        PersonCreationService.new(created_by: Current.user).apply(profile.person) if profile.person&.new_record?

        if profile.save
          render json: serialize(profile).merge("possible_duplicates" => possible_duplicates_for(profile.person)),
                 status: :created
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Editing a profile is a content change: a coach or admin may correct the
      # player's own attributes and the person's contact details. The profile
      # cannot be re-pointed at another person (`person_id`) — that is a merge,
      # not an edit — and the person's provenance is never rewritten.
      #
      # The response mirrors show, plus `possible_duplicates`: a correction
      # ("that was Maria, not Ana") is exactly when a duplicate shows up.
      #
      # Soft visibility applies to the edit too: a coach may not edit a private
      # player they cannot see (404, same as show), and the visibility switch
      # itself may be flipped only by the owner or an admin.
      def update
        unless @player.visible_to_user?(Current.user)
          return render json: { error: "Player not found" }, status: :not_found
        end

        if params.require(:player)[:person_id].present? &&
           params.require(:player)[:person_id].to_i != @player.person_id
          return render json: { errors: [ "This profile already belongs to a person; changing it is a merge, not an edit." ] },
                        status: :unprocessable_entity
        end

        update_params = player_update_params
        requested_visibility = update_params[:visibility] || update_params["visibility"]
        if requested_visibility.present? && requested_visibility.to_s != @player.visibility.to_s &&
           !@player.visibility_change_permitted?(Current.user)
          @player.errors.add(:visibility, "can only be changed by the coach who recorded this player or an admin")
          return render json: { errors: @player.errors.full_messages }, status: :forbidden
        end

        if @player.update(update_params)
          render json: serialize(@player).merge("possible_duplicates" => possible_duplicates_for(@player.person))
        else
          render json: { errors: @player.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      # The catalogue lists active players; an explicit status filter replaces
      # that default instead of adding to it (filtering `.active` *and* archived
      # could only ever return nothing).
      def profile_scope
        status = params[:status].presence

        status ? PlayerProfile.where(status: status) : PlayerProfile.active
      end

      def validate_status_filter!
        return if params[:status].blank? || PlayerProfile::STATUSES.include?(params[:status])

        render json: { errors: [ "status is not included in the list" ] }, status: :unprocessable_entity
      end

      def set_player
        @player = PlayerProfile
                    .includes(:person, :created_by, training_session_participants: :training_session)
                    .find(params[:id])
      end

      def serialize(profile)
        payload = profile.as_json(
          only: PROFILE_ONLY,
          include: {
            person: { only: PERSON_ONLY },
            created_by: { only: %i[id name] }
          },
          methods: PROFILE_METHODS
        )
        # `as_json(include:)` drops a nil `belongs_to`, but the SPA relies on
        # the key always being present (nil = recorded before Phase C).
        payload["created_by"] = nil unless payload.key?("created_by")
        payload
      end

      # People who may already describe this human, matched by email then name.
      # The person just created is excluded so it never suggests itself.
      def possible_duplicates_for(person)
        PersonDuplicateFinder.new(
          first_name: person.first_name,
          last_name: person.last_name,
          email: person.email
        ).matches.reject { |match| match.id == person.id }.map(&:identity_summary)
      end

      def player_params
        attrs = params.require(:player)
        profile_attrs = normalize_attrs(attrs[:player_profile] || attrs[:player_profile_attributes] || {}, PROFILE_ATTRS)

        if attrs[:person_id].present?
          # Link the profile to an existing identity (chosen from the people
          # search); never rewrite that person's provenance.
          profile_attrs[:person_id] = attrs[:person_id]
        else
          person_attrs = normalize_person_attrs(attrs[:person] || attrs[:person_attributes] || {})
          profile_attrs[:person_attributes] = person_attrs if person_attrs.values.any?(&:present?)
        end

        profile_attrs
      end

      # On update the person already exists, so the nested attributes are
      # assigned whenever the key is sent at all — a blank value is meaningful
      # there (clearing a phone number or an email address).
      def player_update_params
        attrs = params.require(:player)
        profile_attrs = normalize_attrs(attrs[:player_profile] || attrs[:player_profile_attributes] || {}, PROFILE_ATTRS)

        person_source = attrs[:person] || attrs[:person_attributes]
        profile_attrs[:person_attributes] = normalize_person_attrs(person_source) if person_source.present?

        profile_attrs
      end

      def normalize_attrs(source, allowed)
        if source.respond_to?(:permit)
          source.permit(*allowed).to_h
        else
          source.stringify_keys.slice(*allowed.map(&:to_s))
        end
      end

      # A blank contact field means "no value", so it is stored as NULL rather
      # than an empty string — and on update it is how a field gets cleared.
      def normalize_person_attrs(source)
        normalize_attrs(source, PERSON_ATTRS).transform_values do |value|
          value.is_a?(String) && value.strip.empty? ? nil : value
        end
      end
    end
  end
end
