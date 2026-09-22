module Api
  module V1
    class PlayersController < ApplicationController
      include ContentAuthorization

      before_action :require_authentication
      before_action :set_player, only: %i[show]

      PERSON_ATTRS = %i[first_name last_name email phone date_of_birth].freeze
      PROFILE_ATTRS = %i[preferred_position level status].freeze

      def index
        players = PlayerProfile.active
                               .includes(:person)
                               .order(:last_name, :first_name, :id)

        if params[:q].present?
          term = "%#{params[:q]}%"
          players = players.where("people.last_name ILIKE :t OR people.first_name ILIKE :t OR people.email ILIKE :t",
                                  t: term)
        end
        if params[:email].present?
          players = players.where(people: { email: params[:email] })
        end
        if params[:status].present?
          players = players.where(status: params[:status])
        end

        render json: players,
               only: %i[id person_id preferred_position level status created_at updated_at],
               include: {
                 person: { only: %i[id first_name last_name email phone date_of_birth creation_source] }
               },
               methods: [:full_name, :account_status]
      end

      def show
        render json: @player,
               only: %i[id person_id preferred_position level status created_at updated_at],
               include: {
                 person: { only: %i[id first_name last_name email phone date_of_birth creation_source] },
                 training_session_participants: { only: %i[id status notes created_at] }
               },
               methods: [:full_name, :account_status]
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Player not found" }, status: :not_found
      end

      def create
        require_training_manager!

        profile = PlayerProfile.new(player_params)
        profile.status ||= "active"
        profile.created_by = Current.user

        if profile.save
          render json: profile,
                 status: :created,
                 only: %i[id person_id preferred_position level status created_at updated_at],
                 include: {
                   person: { only: %i[id first_name last_name email phone date_of_birth creation_source] }
                 },
                 methods: [:full_name, :account_status]
        else
          render json: { errors: profile.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_player
        @player = PlayerProfile.includes(:person).find(params[:id])
      end

      def player_params
        attrs = params.require(:player)
        person_attrs = normalize_attrs(attrs[:person] || attrs[:person_attributes] || {}, PERSON_ATTRS)
        profile_attrs = normalize_attrs(attrs[:player_profile] || attrs[:player_profile_attributes] || {}, PROFILE_ATTRS)

        profile_attrs[:person_attributes] = person_attrs if person_attrs.values.any?(&:present?)
        profile_attrs
      end

      def normalize_attrs(source, allowed)
        if source.respond_to?(:permit)
          source.permit(*allowed).to_h
        else
          source.stringify_keys.slice(*allowed.map(&:to_s))
        end
      end
    end
  end
end
