module Api
  module V1
    class MeController < ApplicationController
      before_action :require_authentication

      def show
        user = Current.user
        render json: { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
      end
    end
  end
end
