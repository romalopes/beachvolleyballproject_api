module Admin
  class DrillsController < ApplicationController
    before_action :authorize_admin!
    before_action :set_drill, only: [:show, :edit, :update, :destroy]

    def index
      @filters = filter_params
      @drills = filtered_drills(@filters)
      @range_error = range_error?(@filters)
    end

    def show
    end

    def new
      @drill = Drill.new
    end

    def edit
    end

    def create
      @drill = Drill.new(drill_params)
      if @drill.save
        redirect_to admin_drill_path(@drill), notice: "Drill was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @drill.update(drill_params)
        redirect_to admin_drill_path(@drill), notice: "Drill was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      reasons = []
      reasons << "#{@drill.media_assets.count} media asset(s)" if @drill.media_assets.any?
      reasons << "#{@drill.training_sessions.count} training session(s)" if @drill.training_sessions.any?
      reasons << "#{@drill.skills.count} skill(s)" if @drill.skills.any?

      if reasons.any?
        redirect_to admin_drills_path, alert: "Cannot delete this drill because it is used by #{reasons.join(', ')}."
        return
      end
      @drill.destroy
      redirect_to admin_drills_path, notice: "Drill was successfully deleted."
    end

    private

    def set_drill
      @drill = Drill.includes(skills: :category).find_by(slug: params[:id]) || Drill.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_drills_path, alert: "Drill not found."
    end

    def drill_params
      params.require(:drill).permit(:title, :setup_instructions, :training_stage, :difficulty_level,
                                     :min_players, :max_players, :ideal_num_players)
    end

    SORT_OPTIONS = %w[name-asc name-desc stage difficulty].freeze

    def filter_params
      params.permit(:q, :stage, :difficulty, :min_players, :max_players, :skill_id, :sort).to_h
    end

    def filtered_drills(filters)
      scope = Drill.includes(skills: :category)

      q = filters[:q].to_s.strip
      if q.present?
        scope = scope.where("drills.title ILIKE ?", "%#{Drill.sanitize_sql_like(q)}%")
      end

      skill_id = Integer(filters[:skill_id].to_s, exception: false)
      if skill_id && Skill.exists?(skill_id)
        scope = scope.joins(:drill_skills).where(drill_skills: { skill_id: skill_id }).distinct
      end

      stage = filters[:stage].to_s
      scope = scope.where(training_stage: stage) if Drill::TRAINING_STAGES.include?(stage)

      difficulty = filters[:difficulty].to_s
      scope = scope.where(difficulty_level: difficulty) if Drill::DIFFICULTY_LEVELS.include?(difficulty)

      filter_min = integer_param(filters[:min_players])
      filter_max = integer_param(filters[:max_players])

      if filter_min && filter_max && filter_min > filter_max
        return Drill.none
      end
      # Overlap semantics on the drill's own stored range.
      scope = scope.where("drills.max_players >= ?", filter_min) if filter_min
      scope = scope.where("drills.min_players <= ?", filter_max) if filter_max

      case filters[:sort].to_s
      when "name-desc"
        scope.order(title: :desc)
      when "stage"
        scope.order(Arel.sql(stage_case_sql), title: :asc)
      when "difficulty"
        scope.order(Arel.sql(difficulty_case_sql), title: :asc)
      else
        scope.order(title: :asc)
      end
    end

    def integer_param(value)
      Integer(value.to_s, exception: false)
    end

    def range_error?(filters)
      filter_min = integer_param(filters[:min_players])
      filter_max = integer_param(filters[:max_players])
      filter_min && filter_max && filter_min > filter_max
    end

    def stage_case_sql
      cases = Drill::TRAINING_STAGES.each_with_index.map do |stage, i|
        "WHEN '#{Drill.sanitize_sql_like(stage)}' THEN #{i}"
      end.join(" ")
      "CASE drills.training_stage #{cases} ELSE #{Drill::TRAINING_STAGES.length} END"
    end

    def difficulty_case_sql
      cases = Drill::DIFFICULTY_LEVELS.each_with_index.map do |level, i|
        "WHEN '#{Drill.sanitize_sql_like(level)}' THEN #{i}"
      end.join(" ")
      "CASE drills.difficulty_level #{cases} ELSE #{Drill::DIFFICULTY_LEVELS.length} END"
    end
  end
end

