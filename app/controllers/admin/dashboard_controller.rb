module Admin
  class DashboardController < ApplicationController
    before_action :authorize_admin!

    def index
      @skills_count = Skill.count
      @categories_count = Category.count
      @drills_count = Drill.count
    end
  end
end
