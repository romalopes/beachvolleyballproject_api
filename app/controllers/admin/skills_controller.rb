module Admin
  class SkillsController < ApplicationController
    before_action :authorize_admin!
    before_action :set_skill, only: [:show, :edit, :update, :destroy]

    def index
      @filters = filter_params
      @skills = filtered_skills(@filters)
      @categories = Category.order(:name)
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

    SORT_OPTIONS = %w[name-asc name-desc category].freeze

    def filter_params
      params.permit(:q, :category_id, :sort).to_h
    end

    def filtered_skills(filters)
      scope = Skill.includes(:category, :drills)

      q = filters[:q].to_s.strip
      if q.present?
        scope = scope.where("skills.title ILIKE ?", "%#{Skill.sanitize_sql_like(q)}%")
      end

      category_id = Integer(filters[:category_id].to_s, exception: false)
      if category_id && Category.exists?(category_id)
        scope = scope.where(category_id: category_id)
      end

      case filters[:sort].to_s
      when "name-desc"
        scope.order(title: :desc)
      when "category"
        scope.left_joins(:category).order(Arel.sql("categories.name ASC NULLS LAST, skills.title ASC"))
      else
        scope.order(title: :asc)
      end
    end
  end
end
