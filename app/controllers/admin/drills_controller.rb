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
  end
end

