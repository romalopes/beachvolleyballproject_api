module Api
  module V1
    module Admin
      class DrillsController < ApplicationController
        include RequestLogging
        before_action :authorize_admin!
        before_action :set_drill, only: [ :show, :update, :destroy ]

        def index
          @drills = Drill.includes([ :training_sessions, { video_references: :video }, skills: :category ])
                          .order(:title)
          # `except` drops the heavy definition blob; `has_definition` tells the
          # client whether a visualisation exists without transferring it.
          render json: @drills, except: [ :definition ], methods: [ :has_definition ], include: {
            skills: { only: [ :id, :title, :slug ], include: { category: { only: [ :id, :name, :slug ] } } },
            training_sessions: { only: [ :id, :title, :starts_at, :ends_at, :location, :status ] }
          }
        end

        def show
          render json: @drill, include: {
            skills: { only: [ :id, :title, :description, :slug ], include: { category: { only: [ :id, :name, :slug ] } } },
            video_references: {
              only: VideoReferencesController::REFERENCE_ONLY,
              methods: VideoReferencesController::REFERENCE_METHODS,
              include: { video: { only: VideoReferencesController::VIDEO_ONLY, methods: VideoReferencesController::VIDEO_METHODS } }
            },
            training_sessions: { only: [ :id, :title, :starts_at, :ends_at, :location, :status ] }
          }
        end

        def create
          skill_ids = Array(params[:drill][:skill_ids]).reject(&:blank?).map(&:to_i).uniq
          if skill_ids.empty?
            render json: { errors: [ "Skills must include at least one skill" ] }, status: :unprocessable_entity
            return
          end

          @drill = Drill.new(drill_params.except(:skill_ids).merge(created_by: Current.user))

          if @drill.save
            assign_skills(@drill, skill_ids)
            render json: @drill, status: :created, include: {
              skills: { only: [ :id, :title, :slug ], include: { category: { only: [ :id, :name, :slug ] } } }
            }
          else
            render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def update
          if params[:drill].key?(:skill_ids)
            skill_ids = Array(params[:drill][:skill_ids]).reject(&:blank?).map(&:to_i).uniq
            if skill_ids.empty?
              render json: { errors: [ "Skills must include at least one skill" ] }, status: :unprocessable_entity
              return
            end
          end

          if @drill.update(drill_params.except(:skill_ids))
            assign_skills(@drill, params[:drill][:skill_ids]) if params[:drill].key?(:skill_ids)
            render json: @drill, include: {
              skills: { only: [ :id, :title, :slug ], include: { category: { only: [ :id, :name, :slug ] } } }
            }
          else
            render json: { errors: @drill.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          reasons = []
          reasons << "#{@drill.video_references.count} video reference(s)" if @drill.video_references.any?
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

        def assign_skills(drill, skill_ids)
          return if skill_ids.nil?

          ids = Array(skill_ids).reject(&:blank?).map(&:to_i).uniq
          # Only keep ids that reference existing skills to avoid FK errors.
          valid_ids = Skill.where(id: ids).pluck(:id)

          drill.drill_skills.destroy_all
          valid_ids.each do |skill_id|
            drill.drill_skills.create!(skill_id: skill_id)
          end
        end

        def set_drill
          @drill = Drill.includes(:training_sessions, { video_references: :video }, skills: :category)
                        .find_by(slug: params[:id]) ||
                    Drill.includes(:training_sessions, { video_references: :video }, skills: :category)
                         .find_by(id: params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Drill not found" }, status: :not_found
        end

        def drill_params
          params.require(:drill).permit(
            :title, :setup_instructions, :training_stage, :difficulty_level,
            :min_players, :max_players, :ideal_num_players,
            skill_ids: [],
            # definition is a JSONB column validated against the v1 schema by the
            # model; permit it as an open hash since its structure is enforced
            # downstream. (A bare :definition symbol would drop the value.)
            definition: {}
          )
        end
      end
    end
  end
end
