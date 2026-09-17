class TrainingSessionsController < ApplicationController
  allow_unauthenticated_access

  def index
    @sessions = TrainingSession
                  .visible_to(Current.user)
                  .includes(:training_focuses, :training_session_drills)
                  .ordered
  end

  def show
    @session = TrainingSession
                 .includes(:created_by, training_focuses: { skill: :category },
                           training_session_drills: { drill: { skills: :category } })
                 .find_by(id: params[:id])
    return render_not_found unless @session && (@session.publicly_visible? || Current.user&.content_manager?)

    @focuses = @session.training_focuses
    @session_drills = @session.training_session_drills
  end

  private

  def render_not_found
    render "shared/not_found", status: :not_found
  end
end
