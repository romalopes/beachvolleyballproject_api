module Api
  module V1
    # Coaches are CoachProfile records, optionally linked to an Account.
    #
    # Access is governed by ProfilePolicy: linked Accounts can view their own
    # profiles, while catalogue access remains role-based. Creating a coach
    # requires a Coach or Admin. A coach with no account can be recorded by
    # staff and used immediately — no Account is created, and no application
    # permissions are granted (those stay role-based on the User).
    class CoachesController < ApplicationController
      include ContentAuthorization
      include Pagination
      include NestedOrganisationMembershipAuthorization

      before_action :require_authentication
      before_action :require_profile_creator!, only: :create
      before_action :set_coach, only: %i[show update merge destroy]
      before_action :validate_status_filter!, only: :index

      PROFILE_ATTRS = %i[display_name email coaching_level qualifications status visibility].freeze

      # Serializable output.
      PROFILE_ONLY = %i[id account_id display_name email coaching_level qualifications status visibility archived_at merged_into_profile_id merged_at created_at updated_at].freeze
      PROFILE_METHODS = %i[full_name account_status coach_profile_id].freeze

      def index
        unless ProfilePolicy.new(actor: Current.user).can_view_collection?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        # See PlayersController: an explicit status filter replaces the active
        # default, so archived coaches stay reachable for restoring.
        #
        # Visibility is the soft variant, same as players: other coaches'
        # private coaches are hidden from the listing; `?include_private=1`
        # reveals them and `?mine=1` narrows to the ones this user recorded.
        coaches = ProfilePolicy.scope(profile_scope, actor: Current.user)
                  .includes(account: :contact_detail)
                  .left_joins(account: :contact_detail)
                  .order(contact_details: { last_name: :asc, first_name: :asc }, coach_profiles: { id: :asc })

        if params[:q].present?
          term = "%#{params[:q]}%"
          email_clause = Current.user.admin? ? " OR contact_details.email ILIKE :t" : ""
          coaches = coaches.where("contact_details.last_name ILIKE :t OR contact_details.first_name ILIKE :t#{email_clause} OR coach_profiles.display_name ILIKE :t",
                                  t: term)
        end
        if params[:email].present? && Current.user.admin?
          coaches = coaches.where(contact_details: { email: params[:email] })
        end
        unless params[:include_private].present?
          coaches = coaches.visible_to(Current.user)
        end
        if params[:mine].present?
          coaches = coaches.owned_by(Current.user)
        end

        records, meta = paginate(coaches)

        render json: {
          data: records.map { |profile| serialize(profile) },
          meta: meta
        }
      end

      # Soft visibility, same as players: a private coach is 404 to a coach who
      # neither owns them nor is a curator/admin.
      def show
        unless ProfilePolicy.new(actor: Current.user, profile: @coach).view?
          return render json: { error: "Coach not found" }, status: :not_found
        end

        payload = @coach.as_json(
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
        redact_contact!(payload, @coach)

        # Attribution history (plan 4.2): the count and a recent slice of the
        # published rows attributed to this coach. Drafts and withdrawn rows
        # are working notes, so they never appear here — the assessments
        # endpoints are where stakeholders reach them.
        payload["assessments_recorded_count"] = @coach.assessments_recorded_count
        payload["recent_assessments"] = @coach.recent_assessments.map(&:metadata)

        render json: payload
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Coach not found" }, status: :not_found
      end

      # A coach recorded through the API is a profile a coach/admin entered.
      # The response carries `possible_duplicates` for API compatibility;
      # profile consolidation happens explicitly through the merge endpoint.
      def create
        attributes = coach_params
        # Self-service from /identity: any authenticated user with an account
        # may create their own linked profile if they don't already have one.
        # Pass `link_to_account: true` in coach_profile from the frontend to opt into self-service.
        # Staff creation of additional unlinked profiles stays coach/admin-only.
        link_to_account = ActiveModel::Type::Boolean.new.cast(params.dig(:coach, :coach_profile, :link_to_account))
        account = Current.user&.account
        if link_to_account
          if account.nil?
            return render json: { errors: [ "Your account is not ready to create a coach profile." ] }, status: :unprocessable_entity
          end
          if account.coach_profiles.exists?
            return render json: { errors: [ "Your account already has a coach profile." ] }, status: :conflict
          end
          attributes = attributes.merge(account_id: account.id)
        elsif Current.user&.coach? || Current.user&.admin?
          # Staff flow: unlinked profile (coach/admin creating additional profiles)
        else
          return render json: { errors: [ "Your account is not ready to create a coach profile." ] }, status: :unprocessable_entity
        end
        profile = CoachProfile.new(attributes)
        saved = CoachProfile.transaction do
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
      def update
        policy = ProfilePolicy.new(actor: Current.user, profile: @coach)
        unless policy.view?
          return render json: { error: "Forbidden" }, status: :forbidden unless policy.manager?

          return render json: { error: "Coach not found" }, status: :not_found
        end
        unless policy.update?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        update_params = coach_update_params
        requested_visibility = update_params[:visibility] || update_params["visibility"]
        if requested_visibility.present? && requested_visibility.to_s != @coach.visibility.to_s &&
           !@coach.visibility_change_permitted?(Current.user)
          @coach.errors.add(:visibility, "can only be changed by the coach who recorded this profile or an admin")
          return render json: { errors: @coach.errors.full_messages }, status: :forbidden
        end

        requested_status = update_params[:status] || update_params["status"]
        if requested_status.present? && requested_status.to_s != @coach.status.to_s && !policy.archive?
          return render json: { error: "Forbidden" }, status: :forbidden
        end

        if @coach.merged?
          return render json: { errors: [ "A merged profile cannot be edited" ] }, status: :unprocessable_entity
        end

        if @coach.update(update_params)
          render json: serialize(@coach).merge("possible_duplicates" => [])
        else
          render json: { errors: @coach.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def merge
        return render json: { error: "Forbidden" }, status: :forbidden unless ProfilePolicy.new(actor: Current.user, profile: @coach).merge?

        canonical = CoachProfile.find(params.require(:canonical_profile_id))
        result = ProfileMergeService.merge!(source: @coach, canonical: canonical,
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
        ProfileDeletionBlocker.destroy!(profile: @coach, user: Current.user)
        head :no_content
      rescue ProfileDeletionBlocker::Blocked => e
        status = e.message == "Forbidden" ? :forbidden : :unprocessable_entity
        render json: { error: e.message, blockers: e.references }, status: status
      rescue ActiveRecord::RecordNotDestroyed
        render json: { error: "Profile could not be deleted", blockers: @coach.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def profile_scope
        status = params[:status].presence

        status ? CoachProfile.where(status: status) : CoachProfile.active
      end

      def validate_status_filter!
        return if params[:status].blank? || CoachProfile::STATUSES.include?(params[:status])

        render json: { errors: [ "status is not included in the list" ] }, status: :unprocessable_entity
      end

      def set_coach
        @coach = CoachProfile.includes(:account, :created_by).find(params[:id])
      end

      def serialize(profile)
        payload = profile.as_json(
          only: PROFILE_ONLY,
          include: {
            created_by: { only: %i[id name] },
            account: { only: :id, methods: :full_name }
          },
          methods: PROFILE_METHODS
        )
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

      def coach_params
        attrs = params.require(:coach)
        profile_attrs = normalize_attrs(attrs[:coach_profile] || attrs[:coach_profile_attributes] || {}, PROFILE_ATTRS)

        profile_attrs
      end

      def coach_update_params
        attrs = params.require(:coach)
        profile_attrs = normalize_attrs(attrs[:coach_profile] || attrs[:coach_profile_attributes] || {}, PROFILE_ATTRS)

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
