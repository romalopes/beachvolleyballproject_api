module Api
  module V1
    class DrillsController < ApplicationController
      include ContentAuthorization
      before_action :set_drill, only: [:show, :update, :destroy]
      before_action :require_content_creator!, only: :create

      def index
        @drills = Drill.includes(skills: :category).all
        render json: @drills, except: [:definition], include: {
          skills: { only: [:id, :title, :slug], include: { category: { only: [:id, :name, :slug] } } }
        }
      end

      def show
        render json: @drill, include: {
          skills: { only: [:id, :title, :description, :slug], include: { category: { only: [:id, :name, :slug] } } },
          media_assets: { only: [:id, :title, :slug, :asset_type, :video_url, :thumbnail_url] },
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
        @drill = Drill.includes(:media_assets, :training_sessions, skills: :category)
                      .find_by(slug: params[:id]) ||
                Drill.includes(:media_assets, :training_sessions, skills: :category)
                     .find_by(id: params[:id])
        authorize_content_owner!(@drill.created_by) unless action_name == "show"
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Drill not found" }, status: :not_found
      end

      def drill_params
        params.require(:drill).permit(
          :title, :setup_instructions, :training_stage, :difficulty_level,
          :min_players, :max_players, :ideal_num_players
        ).to_h.tap do |whitelisted|
          # definition is a JSONB column validated against the v1 schema by the model;
          # permit it as a raw hash since its structure is enforced downstream.
          raw = params[:drill][:definition]
          if raw.present?
            whitelisted["definition"] = raw.is_a?(Hash) ? raw : raw.to_unsafe_h
          end
        end
      end
    end
  end
end