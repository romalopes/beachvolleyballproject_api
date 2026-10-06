module Api
  module V1
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access only: :create

      def create
        user = User.new(registration_params)

        registered = User.transaction do
          next false unless user.save

          user.add_role(:player)
          # Every newly registered authentication identity receives its
          # Account and required ContactDetail atomically. Email verification
          # still gates session creation and invitation acceptance.
          Account.create!(user: user) unless user.account
          true
        end

        if registered

          # Email verification is required before ANY session (API grant or
          # cookie) may be created — an unverified signup must get 202
          # pending_verification, never a token.
          if user.email_verification_pending?
            raw_token = nil
            if EmailVerification.auto_send_on_signup?
              raw_token = EmailVerificationService.send_verification(user)
            end
            render json: user_payload(user).merge(
              status: "pending_verification",
              email: user.email_address,
              verification_token: raw_token,
              message: "Please check your email to verify your account."
            ), status: :accepted
            return
          end

          if api_grant?
            session = start_api_session_for(user)
            Current.session = session
            render json: user_payload(user).merge(token: session.api_token), status: :created
          else
            render json: user_payload(user), status: :created
          end
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def api_grant?
        params[:api] == "true" || params[:api] == true
      end

      def user_payload(user)
        { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
      end

      def registration_params
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
