module Api
  module V1
    # The weighted configurations a coach builds once and applies to players
    # ("A-Level Assessment" = Attack 40 · Defense 30 · Serve 30).
    #
    # Read is open to training managers; creation needs a content creator;
    # editing needs to be the author or oversight — the same three gates
    # AssessmentsController uses (plan D13), because a definition is club
    # configuration a coach owns rather than a row about a particular player.
    #
    # There is no destroy for a *referenced* definition: the model refuses to
    # reconfigure one that results already quote (D7), so that failure surfaces
    # here as a 422 carrying the model's own message.
    #
    # Retirement is admin-only in both directions. Archiving is the reversible soft
    # delete; `destroy` is the hard one, refused while anything still points at the
    # definition, so a historical score can never lose the configuration that gives
    # it meaning.
    class AssessmentDefinitionsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: :create
      before_action :set_definition,
                    only: %i[show update reorder archive restore destroy]
      before_action :require_admin_for_retirement!, only: %i[archive restore destroy]

      def index
        rows = AssessmentDefinition
                 .with_status(params[:status])
                 .ordered
                 .includes(:created_by, :assessment_categories)
        records, meta = paginate(rows)

        render json: {
          data: records.map { |row| row.metadata },
          meta: meta
        }
      end

      def show
        render json: @definition.metadata
      end

      def create
        attributes = definition_params
        fill_missing_positions!(attributes)
        @definition = AssessmentDefinition.new(attributes)
        @definition.created_by = Current.user

        if @definition.save
          render json: @definition.metadata, status: :created
        else
          render json: { errors: @definition.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: [ "That category is already in this definition" ] },
               status: :unprocessable_entity
      end

      def update
        return render json: { error: "Forbidden" }, status: :forbidden unless manageable?

        attributes = definition_params
        fill_missing_positions!(attributes)

        if @definition.update(attributes)
          render json: @definition.metadata
        else
          render json: { errors: @definition.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: [ "That category is already in this definition" ] },
               status: :unprocessable_entity
      end

      # Presentation order only — the calculation is a sum over weights and does
      # not care. Every category must be listed exactly once, which is what lets
      # the client own the drag-and-drop state while the server stays the
      # authority on what the order is.
      def reorder
        return render json: { error: "Forbidden" }, status: :forbidden unless manageable?
        return frozen_definition unless @definition.assessment_categories.empty? || !@definition.referenced?

        ids = Array(params[:ids]).map(&:to_i)
        expected = @definition.assessment_categories.pluck(:id).sort
        unless ids.sort == expected
          return render json: { errors: [ "Reorder must list every category exactly once" ] },
                        status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          ids.each_with_index do |id, index|
            AssessmentCategory
              .where(id: id, assessment_definition_id: @definition.id)
              .update_all(position: index, updated_at: Time.current)
          end
        end
        @definition.reload

        render json: @definition.metadata
      end

      # Soft delete. Archiving takes a definition out of circulation without
      # destroying it, and is never blocked by usage: a configuration people are
      # still scoring against is exactly the one an admin may want hidden. It comes
      # back through `restore`, which is why this is not `destroy`.
      def archive
        unless @definition.archivable?
          return render json: { errors: [ "This assessment definition is already archived" ] },
                        status: :unprocessable_entity
        end

        @definition.update!(status: "archived")

        render json: @definition.metadata
      end

      # Undo an archive. Restored to `draft` rather than to whatever it was before:
      # weights may have drifted, and `active` demands a balanced total, so coming
      # back as a draft is the state that cannot be wrong.
      def restore
        unless @definition.restorable?
          return render json: { errors: [ "This assessment definition is not archived" ] },
                        status: :unprocessable_entity
        end

        @definition.update!(status: "draft")

        render json: @definition.metadata
      end

      # Hard delete, for a definition nothing points at. The usage check is
      # deliberately explicit and names the blockers: the alternative is a foreign
      # key violation surfacing as a 500, or — worse — a definition being removed
      # while a published ranking still claims to be built on it.
      def destroy
        unless @definition.deletable?
          return render json: {
            errors: [
              "This assessment definition is in use by #{@definition.usage_summary}, " \
              "so it cannot be deleted. Archive it instead."
            ]
          }, status: :unprocessable_entity
        end

        @definition.destroy!

        render json: { message: "Assessment definition deleted", id: params[:id] }
      end

      private

      # Retirement is admin-only, curator included: a curator oversees content but
      # is not a content creator, and removing a shared configuration is a bigger
      # claim than reading or editing one.
      def require_admin_for_retirement!
        return true if Current.user&.admin?

        render json: { error: "Only an admin can archive or delete an assessment definition" },
               status: :forbidden
        false
      end

      def set_definition
        @definition = AssessmentDefinition
                        .includes(:created_by, :assessment_categories)
                        .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Assessment definition not found" }, status: :not_found
      end

      def definition_params
        params.require(:assessment_definition).permit(
          :name, :description, :status,
          assessment_categories_attributes: %i[
            id category_id category_custom_id weight position _destroy
          ]
        )
      end

      def manageable?
        Assessment.oversight?(Current.user) ||
          @definition.created_by_id.present? && @definition.created_by_id == Current.user&.id
      end

      # The model refuses the same thing during validation; rendering it here
      # keeps the frozen-definition message identical on every path that can
      # reach it (update and reorder both write the configuration).
      def frozen_definition
        render json: { errors: [ "This assessment definition is in use; duplicate it to make changes." ] },
               status: :unprocessable_entity
      end

      # Mirrors TrainingSessionsController#fill_missing_positions!: a submission
      # that omits a position gets its array index, so the order the coach sees
      # in the editor is the order that is stored.
      def fill_missing_positions!(permitted)
        rows = permitted[:assessment_categories_attributes]
        return if rows.blank?

        rows.each_with_index do |row, index|
          row["position"] = index if row["position"].blank?
        end
      end
    end
  end
end
