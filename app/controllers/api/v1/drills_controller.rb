module Api
  module V1
    class DrillsController < ApplicationController
      before_action :set_drill, only: [:show, :update, :destroy]

      def index
        @drills = Drill.includes(:skills, :media_assets, :training_sessions).all
        render json: @drills, include: [:skills, :media_assets, :training_sessions]
      end

      def show
        render json: @drill, include: [:skills, :media_assets, :training_sessions]
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
        @drill = Drill.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Drill not found" }, status: :not_found
      end

      def drill_params
        params.require(:drill).permit(:title, :setup_instructions, :player_count, :difficulty_level)
      end
    end
  end
end