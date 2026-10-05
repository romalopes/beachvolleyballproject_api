module Api
  module V1
    # One-time bearer invitations for an unlinked player profile. Raw tokens
    # are returned only by create and are never serialized from the model.
    class PlayerClaimInvitationsController < ApplicationController
      include ContentAuthorization

      rate_limit to: 10, within: 1.minute, only: :create
      rate_limit to: 20, within: 1.minute, only: :redeem

      before_action :require_authentication
      before_action :require_content_creator!, only: %i[index create revoke]
      before_action :set_invitation, only: %i[show revoke]

      def index
        profile = PlayerProfile.find_by(id: params[:player_profile_id])
        return render json: { error: "Player profile not found" }, status: :not_found unless profile
        return render json: { error: "Player profile not found" }, status: :not_found unless profile_owner?(profile)

        render json: profile.player_claim_invitations.order(created_at: :desc).map(&:summary)
      end

      def create
        person = Current.user&.person
        return render json: { error: "A linked Person is required to create an invitation" }, status: :unprocessable_entity unless person

        profile = PlayerProfile.find_by(id: params[:player_profile_id])
        return render json: { error: "Player profile not found" }, status: :not_found unless profile
        return render json: { error: "Player profile not found" }, status: :not_found unless profile_owner?(profile)

        invitation, raw_token = PlayerClaimInvitationService.issue!(
          player_profile: profile,
          created_by_person: person,
          invitee_email: invitation_email
        )
        PlayerClaimInvitationDelivery.deliver(invitation: invitation, raw_token: raw_token)
        render json: { invitation: invitation.summary, token: raw_token }, status: :created
      rescue PlayerClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def redeem
        person = Current.user&.person
        return invalid_invitation unless person&.status == "active"

        claim = PlayerClaimInvitationService.redeem!(raw_token: params[:token].to_s, person: person)
        render json: { claim: claim.summary }, status: :created
      rescue PlayerClaimInvitationService::InvitationError
        invalid_invitation
      end

      def show
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?(@invitation)

        render json: @invitation.summary
      end

      def revoke
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?(@invitation)

        invitation = PlayerClaimInvitationService.revoke!(invitation: @invitation)
        render json: invitation.summary
      rescue PlayerClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      private

      # The address an invitation is restricted to. Blank is legitimate and
      # means an open bearer link, so only a *present* malformed value is an
      # error. The format itself is validated by the model, which lets the
      # normal RecordInvalid path report it alongside any other problem.
      def invitation_email
        value = params[:invitee_email]
        return nil if value.nil?

        value.to_s.strip.presence
      end

      def set_invitation
        @invitation = PlayerClaimInvitation.find_by(id: params[:id])
        render json: { error: "Invitation not found" }, status: :not_found unless @invitation
      end

      def profile_owner?(profile)
        Current.user.admin? || (Current.user.coach? && profile.created_by_id == Current.user.id)
      end

      def invitation_owner?(invitation)
        Current.user.admin? || (Current.user.coach? && invitation.player_profile.created_by_id == Current.user.id)
      end

      def invalid_invitation
        render json: { error: PlayerClaimInvitationService::INVALID_MESSAGE }, status: :unprocessable_entity
      end
    end
  end
end
