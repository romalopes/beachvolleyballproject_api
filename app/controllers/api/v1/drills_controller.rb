module Api
  module V1
    class DrillsController < ApplicationController
      include ContentAuthorization
      before_action :set_drill, only: [:show, :update, :destroy]
      before_action :require_content_creator!, only: :create

      def index
        @drills = Drill.includes(skills: :category).all
        render json: @drills, include: {
          skills: { only: [:id, :title], include: { category: { only: [:id, :name] } } }
        }
      end

      def show
        render json: @drill, include: {
          skills: { only: [:id, :title, :description], include: { category: { only: [:id, :name] } } },
          media_assets: { only: [:id, :title, :asset_type, :video_url, :thumbnail_url] },
          training_sessions: { only: [:id, :scheduled_at, :location, :notes] }
        }
      end

      def create
        @drill = Drill.new(drill_params.merge(created_by: Current.user))

        if @drill.save
          render json: @drill, status: :created
        else
          render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @drill.update(drill_params)
          render json: @drill
        else
          render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @drill.destroy
        head :no_content
      end

      private

      def set_drill
        @drill = Drill.includes(:media_assets, :training_sessions, skills: :category).find(params[:id])
        authorize_content_owner!(@drill.created_by) unless action_name == "show"
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Drill not found" }, status: :not_found
      end

      def drill_params
        params.require(:drill).permit(:title, :setup_instructions, :training_stage, :difficulty_level, :min_players, :max_players, :ideal_num_players)
      end
    end
  end
end