module Api
  module V1
    class MeController < ApplicationController
      before_action :require_authentication

      def show
        user = Current.user
        payload = { id: user.id, name: user.name, email_address: user.email_address, roles: user.roles.pluck(:name) }
        if Current.impersonating? && (admin = Current.real_user)
          payload[:impersonating] = true
          payload[:real_admin] = { id: admin.id, name: admin.name, email_address: admin.email_address }
        end
        render json: payload
      end
    end
  end
end
