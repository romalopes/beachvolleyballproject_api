module Api
  module V1
    class DrillSkillsController < ApplicationController
      before_action :set_drill_skill, only: [:show, :update, :destroy]

      def index
        @drill_skills = DrillSkill.includes(:drill, :skill).all
        render json: @drill_skills, include: [:drill, :skill]
      end

      def show
        render json: @drill_skill, include: [:drill, :skill]
      end

      def create
        @drill_skill = DrillSkill.new(drill_skill_params)

        if @drill_skill.save
          render json: @drill_skill, status: :created
        else
          render json: { errors: @drill_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @drill_skill.update(drill_skill_params)
          render json: @drill_skill
        else
          render json: { errors: @drill_skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @drill_skill.destroy
        head :no_content
      end

      private

      def set_drill_skill
        @drill_skill = DrillSkill.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "DrillSkill not found" }, status: :not_found
      end

      def drill_skill_params
        params.require(:drill_skill).permit(:drill_id, :skill_id)
      end
    end
  end
end