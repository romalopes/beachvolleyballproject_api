module Api
  module V1
    class AccountsController < ApplicationController
      before_action :require_authentication

      def show
        render json: account_payload(Current.user.account || Current.user.build_account)
      end

      def update
        account = Current.user.account || Current.user.build_account
        account.build_account_address unless account.account_address

        if account.update(account_params)
          render json: account_payload(account)
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

      def account
        Current.user.account || Current.user.build_account
      end

      def account_payload(account)
        address = account.account_address
        {
          id: account.id,
          first_name: account.first_name,
          last_name: account.last_name,
          phone: account.phone,
          date_of_birth: account.date_of_birth,
          address: {
            street_address: address&.street_address,
            city: address&.city,
            state: address&.state,
            postal_code: address&.postal_code,
            country: address&.country
          }
        }
      end

      def account_params
        params.permit(
          :first_name, :last_name, :phone, :date_of_birth,
          address_attributes: %i[street_address city state postal_code country]
        )
      end
    end
  end
end