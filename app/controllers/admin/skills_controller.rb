module Admin
  class SkillsController < ApplicationController
    before_action :authorize_admin!
    before_action :set_skill, only: [:show, :edit, :update, :destroy]

    def index
      @skills = Skill.includes(:category).order(:title)
    end

    def show
    end

    def new
      @skill = Skill.new
      @categories = Category.order(:name)
    end

    def edit
      @categories = Category.order(:name)
    end

    def create
      @skill = Skill.new(skill_params)
      @categories = Category.order(:name)
      if @skill.save
        redirect_to admin_skill_path(@skill), notice: "Skill was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @categories = Category.order(:name)
      if @skill.update(skill_params)
        redirect_to admin_skill_path(@skill), notice: "Skill was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @skill.drills.any?
        redirect_to admin_skills_path, alert: "Cannot delete this skill because it is used by #{@skill.drills.count} drill(s)."
        return
      end
      @skill.destroy
      redirect_to admin_skills_path, notice: "Skill was successfully deleted."
    end

    private

    def set_skill
      @skill = Skill.find_by(slug: params[:id]) || Skill.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_skills_path, alert: "Skill not found."
    end

    def skill_params
      params.require(:skill).permit(:title, :category_id, :description)
    end
  end
end
