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

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: %i[create update]
      before_action :set_coach, only: %i[show update]
      before_action :validate_status_filter!, only: :index

      # Permitted input.
      PERSON_ATTRS = %i[first_name last_name email phone date_of_birth].freeze
      PROFILE_ATTRS = %i[coaching_level qualifications status].freeze

      # Serializable output.
      PROFILE_ONLY = %i[id person_id coaching_level qualifications status created_at updated_at].freeze
      PERSON_ONLY = %i[id first_name last_name email phone date_of_birth creation_source].freeze
      PROFILE_METHODS = %i[full_name account_status coach_profile_id].freeze

      def index
        # See PlayersController: an explicit status filter replaces the active
        # default, so archived coaches stay reachable for restoring.
        coaches = profile_scope
                  .includes(:person)
                  .joins(:person)
                  .order(people: { last_name: :asc, first_name: :asc }, coach_profiles: { id: :asc })

        if params[:q].present?
          term = "%#{params[:q]}%"
          coaches = coaches.where("people.last_name ILIKE :t OR people.first_name ILIKE :t OR people.email ILIKE :t",
                                  t: term)
        end
        if params[:email].present?
          coaches = coaches.where(people: { email: params[:email] })
        end

        records, meta = paginate(coaches)

        render json: {
          data: records.map { |profile| serialize(profile) },
          meta: meta
        }
      end

      def show
        render json: @coach,
               only: PROFILE_ONLY,
               include: { person: { only: PERSON_ONLY } },
               methods: PROFILE_METHODS
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
        profile = CoachProfile.new(coach_params)
        PersonCreationService.new(created_by: Current.user).apply(profile.person) if profile.person&.new_record?

        if profile.save
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
        if params.require(:coach)[:person_id].present? &&
           params.require(:coach)[:person_id].to_i != @coach.person_id
          return render json: { errors: [ "This profile already belongs to a person; changing it is a merge, not an edit." ] },
                        status: :unprocessable_entity
        end

        if @coach.update(coach_update_params)
          render json: serialize(@coach).merge("possible_duplicates" => possible_duplicates_for(@coach.person))
        else
          render json: { errors: @coach.errors.full_messages }, status: :unprocessable_entity
        end
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
        @coach = CoachProfile.includes(:person).find(params[:id])
      end

      def serialize(profile)
        profile.as_json(
          only: PROFILE_ONLY,
          include: { person: { only: PERSON_ONLY } },
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
          person_attrs = normalize_person_attrs(attrs[:person] || attrs[:person_attributes] || {})
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
