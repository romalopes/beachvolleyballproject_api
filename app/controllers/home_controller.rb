class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    @categories = Category.all
    @skills = Skill.all
    @drills = Drill.all
  end
end