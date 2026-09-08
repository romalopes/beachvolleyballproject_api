module Api
  module V1
    class SessionsController < ApplicationController
      allow_unauthenticated_access only: %i[create destroy]

      def create
        if (user = User.authenticate_by(params.permit(:email_address, :password)))
          start_new_session_for user
          render json: { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
        else
          render json: { error: "Invalid email address or password." }, status: :unauthorized
        end
      end

      def destroy
        resume_session
        terminate_session if Current.session
        head :no_content
      end
    end
  end
end
