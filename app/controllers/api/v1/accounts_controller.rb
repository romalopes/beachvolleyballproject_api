module Api
  module V1
    class AccountsController < ApplicationController
      before_action :require_authentication

      def show
        target = requested_account_id ? viewable_account! : current_account
        return if performed?

        render json: account_payload(target, include_contact: can_manage_account?(target), include_user: Current.user.admin?)
      end

      # Roster management searches recorded Accounts, including Accounts that
      # have not yet been claimed by a login User.
      def search
        return render json: { error: "Forbidden" }, status: :forbidden unless Current.user.content_manager?

        term = params[:q].to_s.strip
        return render json: [] if term.length < 2

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        accounts = Account.joins(:contact_detail)
                          .where("contact_details.first_name ILIKE :q OR contact_details.last_name ILIKE :q OR CONCAT_WS(' ', contact_details.first_name, contact_details.last_name) ILIKE :q", q: pattern)
                          .order("contact_details.last_name", "contact_details.first_name", :id)
                          .limit(25)
        render json: accounts.map { |account| { id: account.id, full_name: account.full_name, account_status: account.claimed? ? "connected" : "unclaimed" } }
      end

      def update
        account = requested_account_id ? editable_account! : current_account
        return if performed?

        account.build_account_address unless account.account_address

        if account.update(account_params)
          render json: account_payload(account, include_contact: true)
        else
          render json: { errors: account.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: ["An account already exists for this user."] }, status: :unprocessable_entity
      end

      def update_password
        user = Current.user
        unless user.authenticate(params[:current_password])
          return render json: { errors: ["Current password is incorrect."] }, status: :unprocessable_entity
        end

        if params[:password].blank? || params[:password].length < 8
          return render json: { errors: ["Password must be at least 8 characters."] }, status: :unprocessable_entity
        end

        if params[:password] != params[:password_confirmation]
          return render json: { errors: ["Password confirmation does not match."] }, status: :unprocessable_entity
        end

        if user.update(password: params[:password], password_confirmation: params[:password_confirmation])
          user.sessions.where.not(id: Current.session.id).destroy_all
          render json: { message: "Password changed successfully." }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def current_account
        Current.user.account || Current.user.build_account
      end

      def editable_account!
        target = Account.find(requested_account_id)
        return target if can_manage_account?(target)

        render json: { error: "Forbidden" }, status: :forbidden
        nil
      end

      def viewable_account!
        target = Account.find(requested_account_id)
        return target if can_view_account?(target)

        render json: { error: "Forbidden" }, status: :forbidden
        nil
      end

      def can_view_account?(target)
        can_manage_account?(target) || Current.user.coach?
      end

      def can_manage_account?(target)
        return false unless target
        return true if Current.user.account&.id == target.id

        Current.user.admin? || Current.user.curator?
      end

      def requested_account_id
        params[:account_id].presence || params[:id].presence
      end

      def account_payload(account, include_contact:, include_user: false)
        address = account.account_address
        payload = {
          id: account.id,
          first_name: include_contact ? account.first_name : nil,
          last_name: include_contact ? account.last_name : nil,
          full_name: account.full_name.presence || "Account ##{account.id}",
          email: include_contact ? account.email : nil,
          phone: include_contact ? account.phone : nil,
          date_of_birth: include_contact ? account.date_of_birth : nil,
          can_edit: can_manage_account?(account),
          address: {
            street_address: include_contact ? address&.street_address : nil,
            city: include_contact ? address&.city : nil,
            state: include_contact ? address&.state : nil,
            postal_code: include_contact ? address&.postal_code : nil,
            country: include_contact ? address&.country : nil
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
        payload[:user] = account_user_payload(account.user) if include_user && account.persisted?
        payload
      end

      def account_user_payload(user)
        return nil unless user

        account = user.account
        {
          id: user.id,
          name: user.name,
          email_address: user.email_address,
          first_name: account&.first_name,
          last_name: account&.last_name,
          account_id: account&.id,
          roles: user.roles.map { |role| { id: role.id, name: role.name } }
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

      def account_params
        permitted = params.permit(
          :first_name, :last_name, :email, :phone, :date_of_birth,
          address: %i[street_address city state postal_code country]
        )
        permitted = permitted.to_h
        if (address = permitted.delete("address") || permitted.delete(:address))
          permitted[:account_address_attributes] = address unless address.values.all?(&:blank?)
        end
        permitted
      end
    end
  end
end
