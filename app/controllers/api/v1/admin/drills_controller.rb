module Api
  module V1
    module Admin
      class DrillsController < ApplicationController
        include RequestLogging
        before_action :authorize_admin!
        before_action :set_drill, only: [:show, :update, :destroy]

        def index
          @drills = Drill.includes([:media_assets, :training_sessions, skills: :category])
                          .order(:title)
          render json: @drills, except: [:definition], include: {
            skills: { only: [:id, :title, :slug], include: { category: { only: [:id, :name, :slug] } } },
            media_assets: { only: [:id, :title, :slug, :asset_type, :video_url, :thumbnail_url] },
            training_sessions: { only: [:id, :scheduled_at, :location, :notes] }
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
            render json: @drill, status: :created, include: {
              skills: { only: [:id, :title, :slug], include: { category: { only: [:id, :name, :slug] } } }
            }
          else
            render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          if @drill.update(drill_params)
            render json: @drill, include: {
              skills: { only: [:id, :title, :slug], include: { category: { only: [:id, :name, :slug] } } }
            }
          else
            render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          reasons = []
          reasons << "#{@drill.media_assets.count} media asset(s)" if @drill.media_assets.any?
          reasons << "#{@drill.training_sessions.count} training session(s)" if @drill.training_sessions.any?
          reasons << "#{@drill.skills.count} skill(s)" if @drill.skills.any?

          if reasons.any?
            render json: {
              error: "Cannot delete this drill because it is used by #{reasons.join(', ')}."
            }, status: :unprocessable_entity
          else
            @drill.destroy
            head :no_content
          end
        end

        private

        def set_drill
          @drill = Drill.includes(:media_assets, :training_sessions, skills: :category)
                        .find_by(slug: params[:id]) ||
                    Drill.includes(:media_assets, :training_sessions, skills: :category)
                         .find_by(id: params[:id])
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
end
