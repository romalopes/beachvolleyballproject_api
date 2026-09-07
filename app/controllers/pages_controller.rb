class PagesController < ApplicationController
  def home
    @categories = Category.all
    @skills = Skill.all
    @drills = Drill.all
  end

  def skills
    @categories = Category.order(:name)
    @skills = Skill.includes(:category).order(:title)
  end

  def skill
    @skill = Skill.includes(:category).find_by(id: params[:id])
    return render_not_found unless @skill

    @related_drills = @skill.drills.includes(skills: :category).order(:title)
  end

  def drills
    @drills = Drill.includes(skills: :category).order(:title)
  end

  def drill
    @drill = Drill.includes(skills: :category).find_by(id: params[:id])
    return render_not_found unless @drill
  end

  def videos
    @videos = MediaAsset.includes(:drill).order(:title)
  end

  def training
    @sessions = TrainingSession.includes(drill: { skills: :category }).order(:scheduled_at)
  end

  def training_session
    @session = TrainingSession.includes(drill: { skills: :category }).find_by(id: params[:id])
    return render_not_found unless @session
  end

  def schedule
    @sessions = TrainingSession.includes(:drill).order(:scheduled_at)
  end

  private

  def render_not_found
    render "pages/not_found", status: :not_found
  end
end
