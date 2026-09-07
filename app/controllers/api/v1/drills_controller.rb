module Api
  module V1
    class DrillsController < ApplicationController
      before_action :set_drill, only: [:show, :update, :destroy]

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
        @drill = Drill.new(drill_params)

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
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Drill not found" }, status: :not_found
      end

      def drill_params
        params.require(:drill).permit(:title, :setup_instructions, :player_count, :difficulty_level)
      end
    end
  end
end