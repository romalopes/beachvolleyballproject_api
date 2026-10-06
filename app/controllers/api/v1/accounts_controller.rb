module Api
  module V1
    class AccountsController < ApplicationController
      before_action :require_authentication

      def show
        target = requested_account_id ? viewable_account! : current_account
        return if performed?

        render json: account_payload(target, include_contact: can_manage_account?(target))
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

      def account_payload(account, include_contact:)
        address = account.account_address
        {
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
          }
        }
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
