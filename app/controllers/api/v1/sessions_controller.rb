module Api
  module V1
    class SessionsController < ApplicationController
      allow_unauthenticated_access only: %i[create destroy]

      def create
        if (user = User.authenticate_by(params.permit(:email_address, :password)))
          if api_grant?
            session = start_api_session_for(user)
            Current.session = session
            render json: user_payload(user).merge(token: session.api_token)
          else
            start_new_session_for user
            render json: user_payload(user)
          end
        else
          render json: { error: "Invalid email address or password." }, status: :unauthorized
        end
      end

      def destroy
        resume_session
        terminate_session if Current.session
        head :no_content
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
