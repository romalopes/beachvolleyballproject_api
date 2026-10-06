module Api
  module V1
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access only: :create

      rate_limit to: 10, within: 1.hour, only: :create

      def create
        unless contact_name_present?
          return render json: { errors: [ "First name and last name are required." ] }, status: :unprocessable_entity
        end

        user = User.new(user_params)

        registered = User.transaction do
          next false unless user.save

          user.add_role(:player)
          # Every newly registered authentication identity receives its
          # Account and required ContactDetail atomically. Email verification
          # still gates session creation and invitation acceptance.
          Account.create!(
            user: user,
            contact_detail: ContactDetail.new(
              first_name: registration_params[:first_name],
              last_name: registration_params[:last_name],
              email: user.email_address
            )
          ) unless user.account
          true
        end

        if registered

          # Email verification is required before ANY session (API grant or
          # cookie) may be created — an unverified signup must get 202
          # pending_verification, never a token.
          if user.email_verification_pending?
            if EmailVerification.auto_send_on_signup?
              EmailVerificationService.send_verification(user)
            end
            render json: user_payload(user).merge(
              status: "pending_verification",
              email: user.email_address,
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
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def api_grant?
        params[:api] == "true" || params[:api] == true
      end

      def user_payload(user)
        { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
      end

      def registration_params
        params.require(:user).permit(:first_name, :last_name, :email_address, :password, :password_confirmation)
      end

      def user_params
        registration_params.slice(:email_address, :password, :password_confirmation)
      end

      def contact_name_present?
        registration_params[:first_name].to_s.strip.present? && registration_params[:last_name].to_s.strip.present?
      end
    end
  end
end
