module Api
  module V1
    class MeController < ApplicationController
      before_action :require_authentication

      def show
        user = Current.user
        person = user.person
        player_profiles = person ? person.player_profiles.order(:id).to_a : []
        player_profile = person&.player_profile
        coach_profiles = person ? person.coach_profiles.order(:id).to_a : []
        active_coach_profiles = coach_profiles.select { |profile| profile.status == "active" }
        # Keep a deterministic legacy default for older SPA clients. New clients
        # should use the complete collection and submit the chosen profile ID.
        coach_profile = active_coach_profiles.first
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
          account_id: user.account&.id,
          player_profile_id: player_profile&.id,
          player_profile_ids: player_profiles.map(&:id),
          player_profiles: player_profiles.map do |profile|
            {
              id: profile.id,
              display_name: profile.display_name,
              preferred_position: profile.preferred_position,
              level: profile.level,
              status: profile.status,
              visibility: profile.visibility
            }
          end,
          coach_profile_id: coach_profile&.id,
          coach_profile_ids: coach_profiles.map(&:id),
          coach_profiles: coach_profiles.map do |profile|
            {
              id: profile.id,
              coaching_level: profile.coaching_level,
              qualifications: profile.qualifications,
              status: profile.status
            }
          end,
          organisation_memberships: person ? person.organisation_memberships.includes(:organisation).order(:id).map do |membership|
            {
              id: membership.id,
              organisation_id: membership.organisation_id,
              role: membership.role,
              status: membership.status,
              joined_at: membership.joined_at,
              left_at: membership.left_at,
              organisation: {
                id: membership.organisation.id,
                name: membership.organisation.name,
                status: membership.organisation.status
              }
            }
          end : [],
          group_memberships: person ? person.group_memberships.includes(group: :organisation).order(:id).map do |membership|
            group = membership.group
            {
              id: membership.id,
              group_id: membership.group_id,
              role: membership.role,
              status: membership.status,
              joined_at: membership.joined_at,
              left_at: membership.left_at,
              group: {
                id: group.id,
                name: group.name,
                status: group.status,
                organisation: group.organisation && { id: group.organisation.id, name: group.organisation.name }
              }
            }
          end : []
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
