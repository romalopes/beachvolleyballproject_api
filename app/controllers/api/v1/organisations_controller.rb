module Api
  module V1
    # A hierarchical organisational context — an international federation, a
    # national body, a state association, a club, an academy.
    #
    # One self-referencing table, never a table per level: the depth is
    # unbounded, so nothing here may assume how many tiers exist and no code may
    # branch on `organisation_type` to decide behaviour.
    #
    # Read is gated the same way as the other people-facing catalogues (groups,
    # players, coaches): a training manager, not any signed-in account. Opening
    # the tree to player accounts would make this the only roster in the app they
    # can read, which is not what "shared context" should mean here.
    class OrganisationsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_organisation_admin!,
                    only: %i[create update archive restore logo]
      before_action :set_organisation,
                    only: %i[show update archive restore logo
                             members create_member update_member end_member]
      # Membership is delegated rather than admin-only, so it is gated separately
      # from the organisation itself. `set_organisation` runs first, so
      # `@organisation` is available; no `with:` lambda, which would pass the
      # organisation in as an argument the method does not take.
      before_action :require_organisation_membership_manager!,
                    only: %i[create_member update_member end_member]

      def index
        organisations = Organisation
                        .with_status(params[:status])
                        .of_type(params[:organisation_type])
                        .ordered
                        .includes(:parent_organisation, :created_by_person, :logo_attachment)
        records, meta = paginate(organisations)

        render json: { data: records.map { |row| serialize(row) }, meta: meta }
      end

      def show
        render json: serialize(@organisation)
      end

      def create
        @organisation = Organisation.new(organisation_params)
        @organisation.created_by_person = Current.user.person

        if @organisation.save
          render json: serialize(@organisation), status: :created
        else
          render json: { errors: @organisation.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update
        if @organisation.update(organisation_params)
          render json: serialize(@organisation)
        else
          render json: { errors: @organisation.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # Upload or replace a logo. A dedicated multipart endpoint rather than a
      # branch inside `update`, so that route keeps a single content-type contract
      # — and because purging an existing logo is its own confirmable action.
      def logo
        file = params[:logo]
        return render json: { errors: [ "A logo file is required" ] },
                      status: :unprocessable_entity if file.blank?

        # Purge first so a replacement does not leave the old blob orphaned behind
        # the attachment. The old file is only unreferenced once the new one lands.
        @organisation.logo.purge if @organisation.logo.attached?
        @organisation.logo.attach(file)

        # `attach` defers saving, so the attachment is only persisted if the record
        # still validates — a rejected content type must not leave a blob behind.
        if @organisation.save
          render json: serialize(@organisation.reload)
        else
          @organisation.logo.purge
          render json: { errors: @organisation.errors.full_messages },
                 status: :unprocessable_entity
        end
      rescue ActiveStorage::FileNotFoundError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :unprocessable_entity
      end

      # Retire an organisation without destroying it. Children are left in place:
      # archiving a club must not silently detach the academy sitting under it.
      def archive
        unless @organisation.archivable?
          return render json: { errors: [ "This organisation is already archived" ] },
                        status: :unprocessable_entity
        end

        @organisation.update!(status: "archived")

        render json: serialize(@organisation)
      end

      def restore
        unless @organisation.restorable?
          return render json: { errors: [ "This organisation is not archived" ] },
                        status: :unprocessable_entity
        end

        @organisation.update!(status: "active")

        render json: serialize(@organisation)
      end

      # --- membership ---------------------------------------------------------
      #
      # Reading the roster is open to any training manager; changing it is delegated
      # to the organisation's own owner and administrators. Unlike the organisation
      # itself, which is a site-level claim, a club's roster is something its own
      # officers should be able to run.

      def members
        render json: {
          organisation: { id: @organisation.id, name: @organisation.name },
          data: visible_memberships.map(&:metadata)
        }
      end

      def create_member
        person = Person.canonical.find_by(id: member_params[:person_id])
        return render json: { errors: [ "Person not found" ] }, status: :not_found if person.nil?

        existing = @organisation.organisation_memberships.find_by(person: person)

        # Already on the roster: nothing was created, so a 201 here would be a lie.
        # 409 rather than 422, because the request was well-formed — the state is
        # what conflicts.
        if existing && !existing.ended?
          return render json: {
            error: "#{person.full_name} is already a member of this organisation",
            membership: existing.metadata
          }, status: :conflict
        end

        # Defaulting to `pending`, not `active`: adding someone to a roster is an
        # invitation, and an invitation is not a grant.
        membership = existing || @organisation.organisation_memberships.build(person: person)
        membership.role = member_params[:role].presence || (existing ? membership.role : "member")
        membership.status = member_params[:status].presence || (existing ? "active" : "pending")

        if membership.save
          render json: membership.metadata, status: :created
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      def update_member
        membership = find_membership
        return if membership.nil?

        membership.role = member_params[:role] if member_params[:role].present?
        membership.status = member_params[:status] if member_params[:status].present?

        if membership.save
          render json: membership.metadata
        else
          render json: { errors: membership.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # Leaving is an `ended` status, never a delete: a historical assessment must
      # still be explicable by the membership that existed when it was recorded.
      def end_member
        membership = find_membership
        return if membership.nil?

        membership.end!

        render json: membership.metadata
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages },
               status: :unprocessable_entity
      end

      private

      # A `pending` invitation is visible only to the people who can act on it. An
      # ended membership is visible to anyone who can see the organisation, because
      # hiding it would erase the very history this feature exists to keep.
      def visible_memberships
        scope = @organisation.organisation_memberships.includes(:person).ordered
        return scope if manageable_membership?
        return scope.ended if Current.user&.person.nil?

        scope.where(person_id: Current.user.person.id)
      end

      def manageable_membership?
        Current.user&.admin? || @organisation.manageable_by?(Current.user&.person)
      end

      def find_membership
        membership = @organisation.organisation_memberships
                                         .includes(:person)
                                         .find_by(person_id: params[:person_id])
        return membership if membership

        render json: { errors: [ "That person is not a member of this organisation" ] },
               status: :not_found
        nil
      end

      # The host has to be threaded in explicitly: a JSON payload cannot rely on
      # the view helper `url_for` that a server-rendered app would use to build a
      # logo URL, so the absolute URL is assembled here.
      def serialize(organisation)
        organisation.metadata(host: request.host)
      end

      def set_organisation
        @organisation = Organisation
                        .includes(:parent_organisation, :created_by_person)
                        .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Organisation not found" }, status: :not_found
      end

      # `status` is writable so a client can archive or restore in one call, but
      # `created_by_person` is deliberately not: attribution is set server-side
      # and is not the caller's to choose.
      def organisation_params
        params.require(:organisation).permit(
          :name, :description, :organisation_type, :status, :parent_organisation_id
        )
      end

      def member_params
        params.require(:membership).permit(:person_id, :role, :status)
      end
    end
  end
end
