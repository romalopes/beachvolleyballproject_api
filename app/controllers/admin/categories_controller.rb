module Admin
  class CategoriesController < ApplicationController
    before_action :authorize_admin!
    before_action :set_category, only: [:show, :edit, :update, :destroy]

    def index
      @categories = Category.includes(:skills).order(:name)
    end

    def show
    end

    def new
      @category = Category.new
    end

    def edit
    end

    def create
      @category = Category.new(category_params)
      if @category.save
        redirect_to admin_category_path(@category), notice: "Category was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @category.update(category_params)
        redirect_to admin_category_path(@category), notice: "Category was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @category.skills.any?
        redirect_to admin_categories_path, alert: "Cannot delete this category because it contains #{@category.skills.count} skill(s). Remove or reassign the skills first."
        return
      end
      @category.destroy
      redirect_to admin_categories_path, notice: "Category was successfully deleted."
    end

    private

    def set_category
      @category = Category.find_by(slug: params[:id]) || Category.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_categories_path, alert: "Category not found."
    end

    def category_params
      params.require(:category).permit(:name)
    end
  end
end
