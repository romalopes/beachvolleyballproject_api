module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authorize_admin!

        def index
          @users = User.includes(:roles).order(:id)
          render json: @users, include: { roles: { only: [:id, :name] } }
        end

        def show
          @user = User.find(params[:id])
          render json: @user, include: { roles: { only: [:id, :name] } }
        end

        # POST /api/v1/admin/users/:id/roles  { role: "coach" }
        def add_role
          @user = User.find(params[:user_id])
          if @user.add_role(params[:role])
            render json: { roles: @user.roles.pluck(:name) }
          else
            render json: { error: "Unknown role" }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/admin/users/:id/roles/:role
        def remove_role
          @user = User.find(params[:user_id])
          role = params[:role]

          if role == "admin" && @user == Current.real_user
            render json: { error: "You cannot remove your own admin role" }, status: :unprocessable_entity
          elsif role == "admin" && @user.admin? && User.joins(:roles).where(roles: { name: "admin" }).count <= 1
            render json: { error: "Cannot remove the last admin" }, status: :unprocessable_entity
          else
            @user.remove_role(role)
            render json: { roles: @user.roles.pluck(:name) }
          end
        end
      end
    end
  end
end
