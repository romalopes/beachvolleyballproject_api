module Api
  module V1
    # Coach-authored rubrics outside the club catalogue ("Mental game").
    #
    # Listing is deliberately narrower than "every row": a private custom
    # category belongs to its creator, so another coach must not be able to
    # discover it through the index — which is the rule `usable_by?` encodes,
    # applied here as a scope instead of a per-row filter after pagination.
    class CategoryCustomsController < ApplicationController
      include ContentAuthorization

      before_action :require_authentication
      before_action :require_training_manager!
      before_action :require_content_creator!, only: :create
      before_action :set_category_custom, only: %i[show update]

      def index
        rows = usable_scope
        rows = rows.where(created_by_id: Current.user.id) if params[:mine].present?

        render json: rows.map(&:metadata)
      end

      def show
        render json: @category_custom.metadata
      end

      def create
        @category_custom = CategoryCustom.new(category_custom_params.merge(created_by: Current.user))

        if @category_custom.save
          render json: @category_custom.metadata, status: :created
        else
          render json: { errors: @category_custom.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        return render json: { error: "Forbidden" }, status: :forbidden unless manageable?

        if @category_custom.update(category_custom_params)
          render json: @category_custom.metadata
        else
          render json: { errors: @category_custom.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_category_custom
        @category_custom = usable_scope.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        # Not visible to this caller is the same answer as not existing.
        render json: { error: "Custom category not found" }, status: :not_found
      end

      def category_custom_params
        params.require(:category_custom).permit(:name, :visibility)
      end

      def manageable?
        @category_custom.manageable_by?(Current.user)
      end

      # What this caller may select from: everything for oversight, otherwise
      # the shared catalogue plus rows they authored themselves.
      def usable_scope
        user = Current.user
        return CategoryCustom.none if user.nil?
        return CategoryCustom.all if Assessment.oversight?(user)

        CategoryCustom.where(visibility: "shared")
                      .or(CategoryCustom.where(created_by_id: user.id))
      end
    end
  end
end
