module Api
  module V1
    class PersonConsolidationsController < ApplicationController
      before_action :require_authentication
      before_action :authorize_admin!

      def preview
        render json: consolidation_preview
      rescue PersonConsolidationService::InvalidConsolidation => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def create
        execute_consolidation
      end

      def resolve
        execute_consolidation(membership_resolutions: params[:membership_resolutions])
      end

      def show
        render json: audit_payload(PersonConsolidation.find(params[:id]))
      end

      private

      def execute_consolidation(membership_resolutions: [])
        source, canonical = selected_people
        audit = PersonConsolidationService.execute!(source_person: source, canonical_person: canonical,
                                                     performed_by: Current.real_user,
                                                     membership_resolutions: membership_resolutions)
        render json: audit_payload(audit), status: :created
      rescue PersonConsolidationService::Conflict => e
        render json: { error: e.message, preview: e.preview }, status: :conflict
      rescue PersonConsolidationService::InvalidConsolidation => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def selected_people
        selection = params.require(:person_consolidation)
        [Person.find(selection.require(:source_person_id)),
         Person.find(selection.require(:canonical_person_id))]
      end

      def consolidation_preview
        source, canonical = selected_people
        PersonConsolidationService.preview(source_person: source, canonical_person: canonical)
      end

      def audit_payload(audit)
        {
          id: audit.id,
          source_person: { id: audit.source_person_id, full_name: audit.source_person.full_name },
          canonical_person: { id: audit.canonical_person_id, full_name: audit.canonical_person.full_name },
          performed_by_id: audit.performed_by_id,
          completed_at: audit.completed_at,
          result: audit.result
        }
      end
    end
  end
end
