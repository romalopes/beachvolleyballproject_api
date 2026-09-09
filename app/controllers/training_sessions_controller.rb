class TrainingSessionsController < ApplicationController
  allow_unauthenticated_access

  def index
    @sessions = TrainingSession.includes(drill: { skills: :category }).order(:scheduled_at)
  end

  def show
    @session = TrainingSession.includes(drill: { skills: :category }).find_by(id: params[:id])
    return render_not_found unless @session
  end

  private

  def render_not_found
    render "shared/not_found", status: :not_found
  end
end