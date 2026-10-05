module Api
  module V1
    # Coaches are CoachProfile records joined to their Person identity.
    #
    # Read access is limited to training managers (coach/curator/admin): the
    # payload carries contact details. Creating a coach additionally requires a
    # content creator (coach/admin). A coach with no account can be recorded by
    # staff and used immediately — no Account is created, and no application
    # permissions are granted (those stay role-based on the User).
    class CoachesController < ApplicationController
      include ContentAuthorization
      include Pagination
      include NestedOrganisationMembershipAuthorization

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: %i[create update]
      before_action :set_coach, only: %i[show update merge destroy]
      before_action :validate_status_filter!, only: :index

      # Permitted input.
      PERSON_ATTRS = %i[first_name last_name email phone date_of_birth].freeze
      PROFILE_ATTRS = %i[coaching_level qualifications status visibility].freeze

      # Serializable output.
      PROFILE_ONLY = %i[id person_id display_name coaching_level qualifications status visibility archived_at merged_into_profile_id merged_at created_at updated_at].freeze
      PERSON_ONLY = %i[id first_name last_name email phone date_of_birth creation_source].freeze
      PROFILE_METHODS = %i[full_name account_status coach_profile_id].freeze

      def index
        # See PlayersController: an explicit status filter replaces the active
        # default, so archived coaches stay reachable for restoring.
        #
        # Visibility is the soft variant, same as players: other coaches'
        # private coaches are hidden from the listing; `?include_private=1`
        # reveals them and `?mine=1` narrows to the ones this user recorded.
        coaches = profile_scope
                  .includes(:person, :created_by)
                  .left_joins(:person)
                  .order(people: { last_name: :asc, first_name: :asc }, coach_profiles: { id: :asc })

        if params[:q].present?
          term = "%#{params[:q]}%"
          coaches = coaches.where("people.last_name ILIKE :t OR people.first_name ILIKE :t OR people.email ILIKE :t OR coach_profiles.display_name ILIKE :t",
                                  t: term)
        end
        if params[:email].present?
          coaches = coaches.where(people: { email: params[:email] })
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
        unless @coach.visible_to_user?(Current.user)
          return render json: { error: "Coach not found" }, status: :not_found
        end

        payload = @coach.as_json(
          only: PROFILE_ONLY,
          include: {
            person: {
              only: PERSON_ONLY,
              include: {
                organisation_memberships: {
                  only: [ :id, :organisation_id, :role, :status ],
                  include: { organisation: { only: [ :id, :name ] } }
                }
              }
            },
            created_by: { only: %i[id name] }
          },
          methods: PROFILE_METHODS
        )
        # `as_json(include:)` drops a nil `belongs_to`, but the SPA relies on
        # the key always being present (nil = recorded before Phase C).
        payload["created_by"] = nil unless payload.key?("created_by")
        # Phase 18 made `person` nullable for coaches, so a coach recorded
        # without an account also arrives without the key.
        payload["person"] = nil unless payload.key?("person")

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

      # A coach recorded through the API is a person a coach/admin entered (not a
      # self-signup): PersonCreationService stamps the provenance and the author
      # so identity resolution can tell the two apart. The response carries
      # `possible_duplicates` — suggestions only, never an automatic merge.
      #
      # Two ways to name the coach: `person_id` links a CoachProfile to a person
      # that already exists (found through /api/v1/people), while nested `person`
      # attributes record a new one.
      def create
        attributes = coach_params
        return unless authorize_nested_organisation_memberships!(
          person: nil, attributes: attributes[:person_attributes] || attributes["person_attributes"] || {}
        )

        profile = CoachProfile.new(attributes)
        saved = CoachProfile.transaction do
          ProfileOwnership.stamp!(profile, Current.user)
          PersonCreationService.new(created_by: Current.user).apply(profile.person) if profile.person&.new_record?
          next true if profile.save

          raise ActiveRecord::Rollback
        end

        if saved
          render json: serialize(profile).merge("possible_duplicates" => possible_duplicates_for(profile.person)),
                 status: :created
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Editing a profile is a content change: a coach or admin may correct the
      # coach's own attributes and the person's contact details. The profile
      # cannot be re-pointed at another person (`person_id`) — that is a merge,
      # not an edit — and the person's provenance is never rewritten.
      def update
        unless @coach.visible_to_user?(Current.user)
          return render json: { error: "Coach not found" }, status: :not_found
        end

        if params.require(:coach)[:person_id].present? &&
           params.require(:coach)[:person_id].to_i != @coach.person_id
          return render json: { errors: [ "This profile already belongs to a person; changing it is a merge, not an edit." ] },
                        status: :unprocessable_entity
        end

        update_params = coach_update_params
        return unless authorize_nested_organisation_memberships!(
          person: @coach.person, attributes: update_params[:person_attributes] || update_params["person_attributes"] || {}
        )
        requested_visibility = update_params[:visibility] || update_params["visibility"]
        if requested_visibility.present? && requested_visibility.to_s != @coach.visibility.to_s &&
           !@coach.visibility_change_permitted?(Current.user)
          @coach.errors.add(:visibility, "can only be changed by the coach who recorded this profile or an admin")
          return render json: { errors: @coach.errors.full_messages }, status: :forbidden
        end

        if @coach.merged?
          return render json: { errors: [ "A merged profile cannot be edited" ] }, status: :unprocessable_entity
        end

        if @coach.update(update_params)
          render json: serialize(@coach).merge("possible_duplicates" => possible_duplicates_for(@coach.person))
        else
          render json: { errors: @coach.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def merge
        return render json: { error: "Forbidden" }, status: :forbidden unless Current.user.admin? || Current.user.curator?

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
        @coach = CoachProfile.includes(:person, :created_by).find(params[:id])
      end

      def serialize(profile)
        profile.as_json(
          only: PROFILE_ONLY,
          include: {
            person: {
              only: PERSON_ONLY,
              include: {
                organisation_memberships: {
                  only: [ :id, :organisation_id, :role, :status ],
                  include: { organisation: { only: [ :id, :name ] } }
                }
              }
            },
            created_by: { only: %i[id name] }
          },
          methods: PROFILE_METHODS
        )
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

      def coach_params
        attrs = params.require(:coach)
        profile_attrs = normalize_attrs(attrs[:coach_profile] || attrs[:coach_profile_attributes] || {}, PROFILE_ATTRS)

        if attrs[:person_id].present?
          # Link the profile to an existing identity (chosen from the people
          # search); never rewrite that person's provenance.
          profile_attrs[:person_id] = attrs[:person_id]
        else
          person_source = attrs[:person] || attrs[:person_attributes] || {}
          person_attrs = normalize_person_attrs(person_source)
          memberships = permit_memberships(person_source)
          person_attrs[:organisation_memberships_attributes] = memberships if memberships.present?
          profile_attrs[:person_attributes] = person_attrs if person_attrs.values.any?(&:present?)
        end

        profile_attrs
      end

      # On update the person already exists, so the nested attributes are
      # assigned whenever the key is sent at all — a blank value is meaningful
      # there (clearing a phone number or an email address).
      def coach_update_params
        attrs = params.require(:coach)
        profile_attrs = normalize_attrs(attrs[:coach_profile] || attrs[:coach_profile_attributes] || {}, PROFILE_ATTRS)

        person_source = attrs[:person] || attrs[:person_attributes]
        if person_source.present?
          person_attrs = normalize_person_attrs(person_source)
          memberships = permit_memberships(person_source)
          person_attrs[:organisation_memberships_attributes] = memberships if memberships.present?
          profile_attrs[:person_attributes] = person_attrs
        end

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

      # Permit nested organisation_memberships_attributes for a person hash.
      # Rails strong-parameters unwrap nested hashes to the parent key, so the
      # permitted result is a hash of the attribute name to the row array — the
      # caller assigns that array, not the wrapper, or Rails sees a second hash
      # where it expects one row per element ("no implicit conversion").
      def permit_memberships(source)
        return nil unless source.respond_to?(:permit)

        permitted = source
                    .permit(organisation_memberships_attributes: [ :id, :organisation_id, :role, :status, :_destroy ])
                    .to_h["organisation_memberships_attributes"]

        # A single row arrives as a hash, not as a one-element array (that is
        # how a form posts it), so normalise it before it reaches Rails. An
        # absent key stays nil, so the caller's `present?` check skips the
        # assignment rather than sending Rails an empty "destroy all" array.
        return nil if permitted.blank?

        permitted.is_a?(Array) ? permitted : [ permitted ]
      end
    end
  end
end
