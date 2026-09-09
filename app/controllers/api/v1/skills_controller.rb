module Api
  module V1
    class SkillsController < ApplicationController
      include ContentAuthorization
      before_action :set_skill, only: [:show, :update, :destroy]
      before_action :require_content_creator!, only: :create

      def index
        @skills = Skill.includes(:category).all
        render json: @skills, include: :category
      end

      def show
        render json: @skill, include: :category
      end

      def create
        @skill = Skill.new(skill_params.merge(created_by: Current.user))

        if @skill.save
          render json: @skill, status: :created
        else
          render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @skill.update(skill_params)
          render json: @skill
        else
          render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @skill.destroy
        head :no_content
      end

      private

      def set_skill
        @skill = Skill.find_by(slug: params[:id]) || Skill.find_by(id: params[:id])
        authorize_content_owner!(@skill.created_by) unless action_name == "show"
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Skill not found" }, status: :not_found
      end

      def skill_params
        params.require(:skill).permit(:title, :category_id, :description)
      end
    end
  end
end