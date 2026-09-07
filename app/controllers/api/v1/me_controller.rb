module Api
  module V1
    class MeController < ApplicationController
      def show
        user = Current.user
        render json: { id: user.id, name: user.name, email_address: user.email_address }
      end
    end
  end
end
