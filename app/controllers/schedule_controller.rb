class ScheduleController < ApplicationController
  allow_unauthenticated_access

  def index
    @sessions = TrainingSession
                  .visible_to(Current.user)
                  .includes(:training_session_drills)
                  .ordered
  end
end
