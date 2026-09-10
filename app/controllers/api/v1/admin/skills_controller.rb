module Api
  module V1
    module Admin
      class SkillsController < ApplicationController
        include RequestLogging
        before_action :authorize_admin!
        before_action :set_skill, only: [:show, :update, :destroy]

        def index
          @skills = Skill.includes(:category, :drills).order(:title)
          render json: @skills, include: { category: { only: [:id, :name, :slug] } }
        end

        def show
          render json: @skill, include: { category: { only: [:id, :name, :slug] } }
        end

        def create
          @skill = Skill.new(skill_params.merge(created_by: Current.user))

          if @skill.save
            render json: @skill, status: :created, include: { category: { only: [:id, :name, :slug] } }
          else
            render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          if @skill.update(skill_params)
            render json: @skill, include: { category: { only: [:id, :name, :slug] } }
          else
            render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          if @skill.drills.any?
            render json: {
              error: "Cannot delete this skill because it is used by #{@skill.drills.count} drill(s)."
            }, status: :unprocessable_entity
          else
            @skill.destroy
            head :no_content
          end
        end

        private

        def set_skill
          @skill = Skill.includes(:category).find_by(slug: params[:id]) ||
                   Skill.includes(:category).find_by(id: params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Skill not found" }, status: :not_found
        end

        def skill_params
          params.require(:skill).permit(:title, :category_id, :description)
        end
      end
    end
  end
end
