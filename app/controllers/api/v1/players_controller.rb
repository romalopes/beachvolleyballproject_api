module Api
  module V1
    # Players are PlayerProfile records, optionally linked to an Account.
    #
    # Access is governed by ProfilePolicy: linked Accounts can view their own
    # profiles, while catalogue access remains role-based. Creating a player
    # requires a Coach or Admin. A player with no account can be recorded by
    # staff and used immediately — no Account is created.
    class PlayersController < ApplicationController
      include ContentAuthorization
      include Pagination
      include NestedOrganisationMembershipAuthorization

      before_action :require_authentication
      before_action :require_profile_creator!, only: :create
      before_action :set_player, only: %i[show update merge destroy]
      before_action :validate_status_filter!, only: :index

      # Permitted input.
      PROFILE_ATTRS = %i[display_name preferred_position level status visibility].freeze

      # Serializable output.
      PROFILE_ONLY = %i[id account_id display_name preferred_position level status visibility archived_at merged_into_profile_id merged_at created_at updated_at].freeze
      PROFILE_METHODS = %i[full_name account_status player_profile_id].freeze
      DETAIL_METHODS = PROFILE_METHODS + %i[training_session_count]

      def index
        unless ProfilePolicy.new(actor: Current.user).can_view_collection?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        # Archived players are hidden from the catalogue by default (they are no
        # longer schedulable) but stay reachable with `?status=archived`, which
        # is how the SPA offers "show archived" and "restore".
        #
        # Visibility is the soft variant: other coaches' private players are
        # hidden from the listing, but the training form's picker must still
        # see everyone (`?include_private=1`) because visibility never blocks
        # scheduling. `?mine=1` narrows to the players this user recorded.
        players = ProfilePolicy.scope(profile_scope, actor: Current.user)
                  .includes(account: :contact_detail)
                  .left_joins(account: :contact_detail)
                  .order(contact_details: { last_name: :asc, first_name: :asc }, player_profiles: { id: :asc })

        if params[:q].present?
          term = "%#{params[:q]}%"
          email_clause = Current.user.admin? ? " OR contact_details.email ILIKE :t" : ""
          players = players.where("contact_details.last_name ILIKE :t OR contact_details.first_name ILIKE :t#{email_clause} OR player_profiles.display_name ILIKE :t",
                                  t: term)
        end
        if params[:email].present? && Current.user.admin?
          players = players.where(contact_details: { email: params[:email] })
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
        unless ProfilePolicy.new(actor: Current.user, profile: @player).view?
          return render json: { error: "Player not found" }, status: :not_found
        end

        payload = @player.as_json(
          only: PROFILE_ONLY,
          include: {
            created_by: { only: %i[id name] },
            account: { only: :id, methods: :full_name },
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
        payload["account"] = nil unless payload.key?("account")
        redact_contact!(payload, @player)

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

      # A player recorded through the API is a profile a coach/admin entered.
      # The response carries `possible_duplicates` for API compatibility;
      # profile consolidation happens explicitly through the merge endpoint.
      def create
        attributes = player_params
        profile = PlayerProfile.new(attributes)
        saved = PlayerProfile.transaction do
          ProfileOwnership.stamp!(profile, Current.user)
          next true if profile.save

          raise ActiveRecord::Rollback
        end

        if saved
          render json: serialize(profile).merge("possible_duplicates" => []),
                 status: :created
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Editing a profile is a content change. Identity consolidation is explicit
      # through the merge endpoint rather than hidden inside an update.
      #
      # Soft visibility applies to the edit too: a coach may not edit a private
      # player they cannot see (404, same as show), and the visibility switch
      # itself may be flipped only by the owner or an admin.
      def update
        policy = ProfilePolicy.new(actor: Current.user, profile: @player)
        unless policy.view?
          return render json: { error: "Forbidden" }, status: :forbidden unless policy.manager?

          return render json: { error: "Player not found" }, status: :not_found
        end
        unless policy.update?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        update_params = player_update_params
        requested_visibility = update_params[:visibility] || update_params["visibility"]
        if requested_visibility.present? && requested_visibility.to_s != @player.visibility.to_s &&
           !@player.visibility_change_permitted?(Current.user)
          @player.errors.add(:visibility, "can only be changed by the coach who recorded this player or an admin")
          return render json: { errors: @player.errors.full_messages }, status: :forbidden
        end

        requested_status = update_params[:status] || update_params["status"]
        if requested_status.present? && requested_status.to_s != @player.status.to_s && !policy.archive?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        if @player.merged?
          return render json: { errors: [ "A merged profile cannot be edited" ] }, status: :unprocessable_entity
        end

        if @player.update(update_params)
          render json: serialize(@player).merge("possible_duplicates" => [])
        else
          render json: { errors: @player.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def merge
        return render json: { error: "Forbidden" }, status: :forbidden unless ProfilePolicy.new(actor: Current.user, profile: @player).merge?

        canonical = PlayerProfile.find(params.require(:canonical_profile_id))
        result = ProfileMergeService.merge!(source: @player, canonical: canonical,
                                            actor: Current.user, reason: params[:reason])
        render json: { id: result.id, source_profile_id: result.source_profile_id,
                       canonical_profile_id: result.canonical_profile_id,
                       reference_counts: result.reference_counts, merged_at: result.created_at }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Profile not found" }, status: :not_found
      rescue ProfileMergeService::Error => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def destroy
        ProfileDeletionBlocker.destroy!(profile: @player, user: Current.user)
        head :no_content
      rescue ProfileDeletionBlocker::Blocked => e
        status = e.message == "Forbidden" ? :forbidden : :unprocessable_entity
        render json: { error: e.message, blockers: e.references }, status: status
      rescue ActiveRecord::RecordNotDestroyed
        render json: { error: "Profile could not be deleted", blockers: @player.errors.full_messages }, status: :unprocessable_entity
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
                    .includes(:account, :created_by, training_session_participants: :training_session)
                    .find(params[:id])
      end

      def serialize(profile)
        can_view_contact = can_view_contact_details?(profile)
        payload = profile.as_json(
          only: PROFILE_ONLY,
          include: {
            created_by: { only: %i[id name] },
            account: { only: :id, methods: :full_name }
          },
          methods: PROFILE_METHODS
        )
        # `as_json(include:)` drops a nil `belongs_to`, but the SPA relies on
        # the key always being present (nil = recorded before Phase C).
        payload["created_by"] = nil unless payload.key?("created_by")
        payload["account"] = nil unless payload.key?("account")
        payload
      end

      def can_view_contact_details?(profile)
        user = Current.user
        return false unless user
        return true if user.admin?

        account = user.account
        account && profile.account_id == account.id
      end

      def redact_contact!(payload, profile)
        return if can_view_contact_details?(profile)

        payload.delete("contact_detail")
      end

      def player_params
        attrs = params.require(:player)
        profile_attrs = normalize_attrs(attrs[:player_profile] || attrs[:player_profile_attributes] || {}, PROFILE_ATTRS)

        profile_attrs
      end

      def player_update_params
        attrs = params.require(:player)
        profile_attrs = normalize_attrs(attrs[:player_profile] || attrs[:player_profile_attributes] || {}, PROFILE_ATTRS)

        profile_attrs
      end

      def normalize_attrs(source, allowed)
        if source.respond_to?(:permit)
          source.permit(*allowed).to_h
        else
          source.stringify_keys.slice(*allowed.map(&:to_s))
        end
      end

    end
  end
end
