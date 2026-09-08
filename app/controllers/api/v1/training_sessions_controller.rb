module Api
  module V1
    class TrainingSessionsController < ApplicationController
      include ContentAuthorization
      before_action :set_training_session, only: [:show, :update, :destroy]
      before_action :require_content_creator!, only: :create

      def index
        @training_sessions = TrainingSession.includes(:drill).all
        render json: @training_sessions, include: :drill
      end

      def show
        render json: @training_session, include: :drill
      end

      def create
        @training_session = TrainingSession.new(training_session_params.merge(created_by: Current.user))

        if @training_session.save
          render json: @training_session, status: :created
        else
          render json: { errors: @training_session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @training_session.update(training_session_params)
          render json: @training_session
        else
          render json: { errors: @training_session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @training_session.destroy
        head :no_content
      end

      private

      def set_training_session
        @training_session = TrainingSession.find(params[:id])
        authorize_content_owner!(@training_session.created_by) unless action_name == "show"
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Training Session not found" }, status: :not_found
      end

      def training_session_params
        params.require(:training_session).permit(:drill_id, :scheduled_at, :location, :notes)
      end
    end
  end
end