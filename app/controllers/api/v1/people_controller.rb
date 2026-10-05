module Api
  module V1
    # Identity search and management over Person records.
    #
    # The search is the lookup the "create player/coach" flow runs *before* creating
    # a new person: a coach searches by name or email, then either picks an
    # existing Person or creates a new one. It returns contact details, so it is
    # limited to staff (coaches/admins) — the same people who may create profiles.
    #
    # The payload is Person#identity_summary, shared with the
    # `possible_duplicates` block returned by Players/Coaches create, so clients
    # render both with one component.
    #
    # Two actions are admin-only because they are irreversible or unusually broad:
    # destroying a person cascades to their player and coach profiles, and
    # promoting somebody attaches a professional profile to an identity that may
    # already have been curated.
    class PeopleController < ApplicationController
      include ContentAuthorization
      include Pagination
      include NestedOrganisationMembershipAuthorization

      before_action :require_authentication
      before_action :require_content_creator!
      before_action :require_admin!, only: %i[destroy promote]
      before_action :set_person, only: %i[show update destroy promote]

      # Bounded so the typeahead stays cheap and cannot be used to dump the whole
      # people table. The management list is paginated instead.
      LIMIT = 25

      # The typeahead. Kept separate from `index` because it has a different shape:
      # a bare array, and a hard cap the caller does not control.
      def search
        render json: scoped_people.limit(LIMIT).map(&:identity_summary)
      end

      def index
        records, meta = paginate(scoped_people)

        render json: { data: records.map(&:identity_summary), meta: meta }
      end

      def show
        render json: @person.identity_summary.merge(
          organisation_memberships: @person.organisation_memberships.includes(:organisation).map do |m|
            { id: m.id, organisation_id: m.organisation_id, role: m.role, status: m.status, organisation: m.organisation&.slice(:id, :name) }
          end
        )
      end

      def create
        attributes = person_params
        return unless authorize_nested_organisation_memberships!(person: nil, attributes: attributes)

        person = Person.new(attributes)
        # Provenance is recorded, not chosen: a person created here was created by
        # staff, whatever the caller asked for.
        person.creation_source = "coach_created"
        person.created_by = Current.user

        if person.save
          render json: person.identity_summary, status: :created
        else
          render json: { errors: person.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        attributes = person_params
        return unless authorize_nested_organisation_memberships!(person: @person, attributes: attributes)

        if @person.update(attributes)
          render json: @person.identity_summary
        else
          render json: { errors: @person.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def destroy
        # Checked *before* attempting the destroy so the caller gets a precise
        # reason instead of a rolled-back transaction, and so no query runs
        # against a row that was never going to be deletable.
        blocker = PersonDeletionBlocker.new(@person)
        if blocker.blocked?
          return render json: {
            error: "This person cannot be deleted.",
            reasons: blocker.messages,
            details: blocker.details,
            # `errors` is what the SPA reads (see `throwApiError`), so the full
            # reason-and-remedy list is carried there too rather than only in
            # `details`, which nothing currently renders.
            errors: [ "This person cannot be deleted.", *blocker.details ]
          }, status: :unprocessable_entity
        end

        @person.destroy!

        render json: { message: "Person deleted", id: params[:id] }
      # `dependent: :restrict_with_error` is signalled by `RecordNotDestroyed`, not
      # by `DeleteRestrictionError` (which is what `restrict` without `_with_error`
      # raises). Catching the wrong one turns a refusal into a 500. The pre-flight
      # check above normally catches these first; this remains the backstop for a
      # record that becomes blocked between the check and the write.
      rescue ActiveRecord::RecordNotDestroyed => e
        render json: {
          error: "This person cannot be deleted.",
          reasons: e.record.errors.full_messages,
          errors: [ "This person cannot be deleted.", *e.record.errors.full_messages ]
        }, status: :unprocessable_entity
      end

      # Attach a player or coach profile to somebody who already exists.
      #
      # This is not the same as creating a player. A brand-new player is a coach's
      # ordinary work, whereas promoting an existing person attaches a
      # professional profile to an identity that may already be on a club's
      # roster, may already carry assessments attributed to them, and may
      # deliberately have been recorded without a profile at all. Hence admin-only.
      def promote
        role = params.require(:promotion)[:role].to_s
        unless %w[player coach].include?(role)
          return render json: { error: "role must be player or coach" },
                        status: :unprocessable_entity
        end

        profile_class = role == "player" ? PlayerProfile : CoachProfile
        profile = profile_class.create!(person: @person, created_by: Current.user)
        render json: @person.reload.identity_summary.merge(profile_id: profile.id,
                                                           profile_kind: role),
               status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages },
               status: :unprocessable_entity
      end

      private

      # Merged and superseded people are excluded: they stay queryable through
      # `merged_into_id`, but offering one for a new profile or membership would
      # duplicate an identity somebody has already reconciled.
      def scoped_people
        people = Person.canonical
                       .includes(:account, :player_profiles, :coach_profiles, :person_aliases)
                       .order(:last_name, :first_name, :id)

        if params[:q].present?
          term = "%#{params[:q]}%"
          # The alias subquery keeps a renamed person findable by the name a coach
          # still knows them by ("Peter Smith" once "Pedro Silva"), and makes
          # duplicate detection work across a rename.
          people = people.where(
            "people.first_name ILIKE :term OR people.last_name ILIKE :term OR people.email ILIKE :term " \
            "OR people.id IN (SELECT person_id FROM person_aliases WHERE full_name ILIKE :term)",
            term: term
          )
        end
        if params[:email].present?
          people = people.where("LOWER(people.email) = ?", params[:email].to_s.strip.downcase)
        end

        people
      end

      def set_person
        @person = Person.canonical.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Person not found" }, status: :not_found
      end

      # `creation_source` and `created_by` are deliberately absent: provenance is
      # recorded by the server, never chosen by the caller, so a person cannot be
      # written in as though they had signed up.
      def person_params
        permitted = params.require(:person).permit(
          :first_name, :last_name, :email, :phone, :date_of_birth,
          organisation_memberships_attributes: [ :id, :organisation_id, :role, :status, :_destroy ]
        ).to_h

        # Strong parameters unwrap the nested hash, so the permitted result wraps
        # the row array one level down. Assign the array itself and normalise a
        # single posted row to a one-element array before it reaches Rails. An
        # absent key is dropped rather than sent as an empty array, which Rails
        # would otherwise read as "destroy every membership".
        rows = permitted["organisation_memberships_attributes"]
        if rows.present?
          permitted["organisation_memberships_attributes"] = rows.is_a?(Array) ? rows : [ rows ]
        else
          permitted.delete("organisation_memberships_attributes")
        end
        permitted
      end
    end
  end
end
