module Api
  module V1
    class PasswordsController < ApplicationController
      allow_unauthenticated_access only: %i[create update]

      # POST /api/v1/passwords — request a reset email
      def create
        if (user = User.find_by(email_address: params[:email_address]))
          PasswordsMailer.reset_password_instructions(user).deliver_later
        end
        head :no_content
      end

      # PUT /api/v1/passwords/:token — set a new password
      def update
        user = User.find_by_password_reset_token!(params[:token])

        if user.update(params.permit(:password, :password_confirmation))
          user.sessions.destroy_all

          if api_grant?
            session = start_api_session_for(user)
            Current.session = session
            render json: user_payload(user).merge(token: session.api_token)
          else
            head :no_content
          end
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        render json: { error: "Password reset link is invalid or has expired." }, status: :unprocessable_entity
      end

      private

      def api_grant?
        params[:api] == "true" || params[:api] == true
      end

      def user_payload(user)
        { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
      end
    end
  end
end
