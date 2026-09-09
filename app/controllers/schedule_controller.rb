class ScheduleController < ApplicationController
  allow_unauthenticated_access

  def index
    @sessions = TrainingSession.includes(:drill).order(:scheduled_at)
  end
end