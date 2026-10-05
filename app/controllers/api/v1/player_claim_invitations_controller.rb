module Api
  module V1
    # Compatibility endpoint. New invitations use ClaimInvitationsController;
    # these routes remain available while existing clients migrate.
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

        render json: profile.claim_invitations.order(created_at: :desc).map(&:summary)
      end

      def create
        profile = PlayerProfile.find_by(id: params[:player_profile_id])
        return render json: { error: "Player profile not found" }, status: :not_found unless profile
        return render json: { error: "Player profile not found" }, status: :not_found unless profile_owner?(profile)

        invitation, raw_token = ClaimInvitationService.issue!(
          claimable: profile,
          invited_by: Current.user,
          invitee_email: invitation_email
        )
        delivered = ClaimInvitationDelivery.deliver(invitation: invitation, raw_token: raw_token)
        ClaimInvitationService.mark_emailed!(invitation: invitation) if delivered
        render json: { invitation: invitation.summary, token: raw_token, email_delivered: delivered }, status: :created
      rescue ClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def redeem
        raw_token = params[:token].to_s
        digest = Digest::SHA256.hexdigest(raw_token.strip)

        if ClaimInvitation.exists?(token_digest: digest, claimable_type: "PlayerProfile")
          result = ClaimInvitationService.redeem!(raw_token: raw_token, user: Current.user)
          payload = { outcome: result[:outcome].to_s, invitation: result[:invitation].summary }
          if result[:outcome] == :linked
            payload[:person] = Current.user.reload.person&.identity_summary
          else
            payload[:claim] = result[:claim].summary
            payload[:message] = "Your request was sent for review. A coach or administrator will approve it."
          end
        else
          # Previously issued legacy links remain redeemable during the
          # compatibility window. They always create a review request; they
          # cannot directly attach a profile to a Person.
          claim = PlayerClaimInvitationService.redeem!(raw_token: raw_token, person: Current.user.person)
          payload = { outcome: "pending_review", claim: claim.summary,
                      message: "Your request was sent for review. A coach or administrator will approve it." }
        end
        render json: payload, status: :created
      rescue ClaimInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue PlayerClaimInvitationService::InvitationError => e
        message = e.message == PlayerClaimInvitationService::INVALID_MESSAGE ? ClaimInvitationService::INVALID_MESSAGE : e.message
        render json: { error: message }, status: :unprocessable_entity
      end

      def show
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?(@invitation)

        render json: @invitation.summary
      end

      def revoke
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?(@invitation)

        invitation = ClaimInvitationService.revoke!(invitation: @invitation)
        render json: invitation.summary
      rescue ClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      private

      # Retained for compatibility with clients that still create invitations
      # through this route.
      def invitation_email
        value = params[:invitee_email]
        return nil if value.nil?

        value.to_s.strip.presence
      end

      def set_invitation
        @invitation = ClaimInvitation.find_by(id: params[:id], claimable_type: "PlayerProfile")
        render json: { error: "Invitation not found" }, status: :not_found unless @invitation
      end

      def profile_owner?(profile)
        Current.user.admin? || (Current.user.coach? && ProfileOwnership.owned_by?(profile, Current.user))
      end

      def invitation_owner?(invitation)
        Current.user.admin? || (Current.user.coach? && ProfileOwnership.owned_by?(invitation.claimable, Current.user))
      end

      def invalid_invitation
        render json: { error: PlayerClaimInvitationService::INVALID_MESSAGE }, status: :unprocessable_entity
      end
    end
  end
end
