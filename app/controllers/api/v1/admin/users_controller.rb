module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authorize_admin!

        # GET /api/v1/admin/users
        # Supports:
        #   search   — case-insensitive substring match on name or email
        #   page     — page number (default 1)
        #   per_page — page size (default 20, clamped 1..100)
        # Returns { data: [...], meta: { page, per_page, total, total_pages } }
        # so the SPA can drive its pagination UI.
        def index
          users = User.includes(:roles).order(:id)

          if params[:search].present?
            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
            users = users.where(
              "users.name ILIKE ? OR users.email_address ILIKE ?",
              pattern, pattern
            )
          end

          page = (params[:page] || 1).to_i
          page = 1 if page < 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          total = users.count
          users = users.offset((page - 1) * per_page).limit(per_page)

          render json: {
            data: users.as_json(include: { roles: { only: [:id, :name] } }),
            meta: {
              page: page,
              per_page: per_page,
              total: total,
              total_pages: (total.to_f / per_page).ceil
            }
          }
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
