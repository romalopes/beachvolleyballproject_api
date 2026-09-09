class DrillsController < ApplicationController
  allow_unauthenticated_access

  def index
    @drills = Drill.includes(skills: :category).order(:title)
  end

  def show
    @drill = Drill.includes(skills: :category).find_by(slug: params[:id]) || Drill.includes(skills: :category).find_by(id: params[:id])
    return render_not_found unless @drill
  end

  private

  def render_not_found
    render "shared/not_found", status: :not_found
  end
end