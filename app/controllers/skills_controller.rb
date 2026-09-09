class SkillsController < ApplicationController
  allow_unauthenticated_access

  def index
    @categories = Category.order(:name)
    @skills = Skill.includes(:category).order(:title)
  end

  def show
    @skill = Skill.includes(:category).find_by(slug: params[:id]) || Skill.includes(:category).find_by(id: params[:id])
    return render_not_found unless @skill

    @related_drills = @skill.drills.includes(skills: :category).order(:title)
  end

  private

  def render_not_found
    render "shared/not_found", status: :not_found
  end
end