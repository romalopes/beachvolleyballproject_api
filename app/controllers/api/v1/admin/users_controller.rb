module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :authorize_admin!

        # GET /api/v1/admin/users
        # Supports:
        #   search   — case-insensitive substring match on email
        #   page     — page number (default 1)
        #   per_page — page size (default 20, clamped 1..100)
        # Returns { data: [...], meta: { page, per_page, total, total_pages } }
        # so the SPA can drive its pagination UI.
        def index
          users = User.includes(:roles, account: :contact_detail).order(:id)

          if params[:search].present?
            pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
            users = users.where("users.email_address ILIKE ?", pattern)
          end

          page = (params[:page] || 1).to_i
          page = 1 if page < 1
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          total = users.count
          users = users.offset((page - 1) * per_page).limit(per_page)

          render json: {
            data: users.map { |user| user_payload(user) },
            meta: {
              page: page,
              per_page: per_page,
              total: total,
              total_pages: (total.to_f / per_page).ceil
            }
          }
        end

        def show
          user = User.includes(
            :roles,
            account: [
              :contact_detail,
              :account_address,
              { organisation_memberships: :organisation },
              { group_memberships: { group: :organisation } },
              :player_profiles,
              :coach_profiles
            ]
          ).find(params[:id])

          render json: user_payload(user, include_account: true)
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

        private

        def user_payload(user, include_account: false)
          account = user.account
          payload = {
            id: user.id,
            name: user.name,
            email_address: user.email_address,
            first_name: account&.first_name,
            last_name: account&.last_name,
            account_id: account&.id,
            roles: user.roles.map { |role| { id: role.id, name: role.name } }
          }

          payload[:account] = account ? account_payload(account) : nil if include_account
          payload
        end

        def account_payload(account)
          address = account.account_address
          {
            id: account.id,
            first_name: account.first_name,
            last_name: account.last_name,
            full_name: account.full_name.presence || "Account ##{account.id}",
            email: account.email,
            phone: account.phone,
            date_of_birth: account.date_of_birth,
            can_edit: true,
            address: {
              street_address: address&.street_address,
              city: address&.city,
              state: address&.state,
              postal_code: address&.postal_code,
              country: address&.country
            },
            player_profiles: account.player_profiles.active.order(:id).map { |profile|
              { id: profile.id, name: profile.full_name.presence || profile.display_name || "Player profile ##{profile.id}" }
            },
            coach_profiles: account.coach_profiles.active.order(:id).map { |profile|
              { id: profile.id, name: profile.full_name.presence || profile.display_name || "Coach profile ##{profile.id}" }
            },
            organisation_memberships: organisation_membership_payloads(account),
            group_memberships: group_membership_payloads(account)
          }
        end

        def organisation_membership_payloads(account)
          account.organisation_memberships.includes(:organisation).order(:id).map do |membership|
            {
              id: membership.id,
              account_id: membership.account_id,
              organisation_id: membership.organisation_id,
              role: membership.role,
              status: membership.status,
              joined_at: membership.joined_at,
              left_at: membership.left_at,
              organisation: {
                id: membership.organisation.id,
                name: membership.organisation.name,
                status: membership.organisation.status
              }
            }
          end
        end

        def group_membership_payloads(account)
          account.group_memberships.includes(group: :organisation).order(:id).map do |membership|
            group = membership.group
            {
              id: membership.id,
              account_id: membership.account_id,
              group_id: membership.group_id,
              role: membership.role,
              status: membership.status,
              joined_at: membership.joined_at,
              left_at: membership.left_at,
              group: {
                id: group.id,
                name: group.name,
                status: group.status,
                organisation: group.organisation && { id: group.organisation.id, name: group.organisation.name }
              }
            }
          end
        end
      end
    end
  end
end
