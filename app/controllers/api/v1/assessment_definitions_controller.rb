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
    # There is no destroy: a definition is archived. The model refuses to
    # reconfigure one that results already quote (D7), so that failure surfaces
    # here as a 422 carrying the model's own message.
    class AssessmentDefinitionsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: :create
      before_action :set_definition, only: %i[show update reorder]

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

      private

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
