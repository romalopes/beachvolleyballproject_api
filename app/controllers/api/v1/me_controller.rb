module Api
  module V1
    class MeController < ApplicationController
      before_action :require_authentication

      def show
        user = Current.user
        person = user.person
        player_profile = person&.player_profile
        coach_profile = person&.coach_profile
        payload = {
          id: user.id,
          name: user.name,
          email_address: user.email_address,
          roles: user.roles.pluck(:name),
          # The SPA records assessments against profiles, not accounts: the
          # assessor defaults to `coach_profile_id`, a missing one explains
          # the "no coach profile yet" affordance, and `player_profile_id`
          # keeps the caller's own player row out of the assessable picker.
          person_id: person&.id,
          player_profile_id: player_profile&.id,
          coach_profile_id: coach_profile&.id
        }
        if Current.impersonating? && (admin = Current.real_user)
          payload[:impersonating] = true
          payload[:real_admin] = { id: admin.id, name: admin.name, email_address: admin.email_address }
        end
        render json: payload
      end
    end
  end
end
