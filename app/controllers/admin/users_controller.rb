module Admin
  class UsersController < ApplicationController
    before_action :authorize_admin!

    def index
      @users = User.includes(:roles).order(:id)
    end

    def add_role
      @user = User.find(params[:id])
      @user.add_role(params[:role])
      redirect_to admin_users_path, notice: "Role added to #{@user.name}."
    end

    def remove_role
      @user = User.find(params[:id])
      role = params[:role]

      if role == "admin" && @user.admin? && User.joins(:roles).where(roles: { name: "admin" }).count <= 1
        redirect_to admin_users_path, alert: "Cannot remove the last admin."
      else
        @user.remove_role(role)
        redirect_to admin_users_path, notice: "Role removed from #{@user.name}."
      end
    end
  end
end
