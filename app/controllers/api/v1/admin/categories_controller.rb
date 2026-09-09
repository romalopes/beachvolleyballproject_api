module Api
  module V1
    module Admin
      class CategoriesController < ApplicationController
        include AdminAudit
        before_action :authorize_admin!
        before_action :set_category, only: [:show, :update, :destroy]

        def index
          @categories = Category.includes(:skills).order(:name)
          render json: @categories
        end

        def show
          render json: @category
        end

        def create
          @category = Category.new(category_params)

          if @category.save
            render json: @category, status: :created
          else
            render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          if @category.update(category_params)
            render json: @category
          else
            render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          if @category.skills.any? && params[:confirm_destroy] != @category.id.to_s
            render json: {
              error: "Cannot delete this category because it contains #{@category.skills.count} skill(s). Set confirm_destroy=#{@category.id} to force removal (skills will also be deleted)."
            }, status: :unprocessable_entity
          else
            @category.destroy
            head :no_content
          end
        end

        private

        def set_category
          @category = Category.find_by(slug: params[:id]) ||
                      Category.find_by(id: params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Category not found" }, status: :not_found
        end

        def category_params
          params.require(:category).permit(:name)
        end
      end
    end
  end
end
