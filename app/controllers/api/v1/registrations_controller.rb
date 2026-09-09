module Api
  module V1
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access only: :create

      def create
        user = User.new(registration_params)

        if user.save
          user.add_role(:player)
          if api_grant?
            session = start_api_session_for(user)
            Current.session = session
            render json: user_payload(user).merge(token: session.api_token), status: :created
          else
            start_new_session_for user
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
