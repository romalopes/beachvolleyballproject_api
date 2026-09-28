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
                    only: %i[show update archive restore logo]

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

      private

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
    end
  end
end
