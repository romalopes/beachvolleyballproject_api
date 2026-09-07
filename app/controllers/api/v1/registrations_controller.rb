module Api
  module V1
    class RegistrationsController < ApplicationController
      allow_unauthenticated_access only: :create

      def create
        user = User.new(registration_params)

        if user.save
          start_new_session_for user
          render json: { id: user.id, name: user.name, email_address: user.email_address }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def registration_params
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end
    end
  end
end
