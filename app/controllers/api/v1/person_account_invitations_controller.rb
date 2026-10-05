module Api
  module V1
    # Compatibility routes for connecting an Account to an already-recorded
    # Person. Records and lifecycle are delegated to ClaimInvitationService.
    class PersonAccountInvitationsController < ApplicationController
      include ContentAuthorization

      rate_limit to: 10, within: 1.minute, only: :create
      rate_limit to: 20, within: 1.minute, only: :redeem

      before_action :require_authentication
      before_action :require_content_creator!, except: :redeem
      before_action :set_person, only: %i[index create]
      before_action :set_invitation, only: :revoke

      def index
        return render json: { error: "Person not found" }, status: :not_found unless person_owner?
        render json: @person.claim_invitations.order(created_at: :desc).map(&:summary)
      end

      def create
        return render json: { error: "Person not found" }, status: :not_found unless person_owner?
        invitation, raw_token = ClaimInvitationService.issue!(claimable: @person, invited_by: Current.user)
        delivered = ClaimInvitationDelivery.deliver(invitation: invitation, raw_token: raw_token)
        ClaimInvitationService.mark_emailed!(invitation: invitation) if delivered

        render json: { invitation: invitation.summary, token: raw_token, email_delivered: delivered }, status: :created
      rescue ClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def revoke
        return render json: { error: "Invitation not found" }, status: :not_found unless Current.user.admin? || Current.user.coach?
        invitation = ClaimInvitationService.revoke!(invitation: @invitation)
        render json: invitation.summary
      rescue ClaimInvitationService::InvitationError => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def redeem
        raw_token = params[:token].to_s
        digest = Digest::SHA256.hexdigest(raw_token.strip)

        if ClaimInvitation.exists?(token_digest: digest, claimable_type: "Person")
          result = ClaimInvitationService.redeem!(raw_token: raw_token, user: Current.user)
          account = Current.user.reload.account
          render json: { invitation: result[:invitation].summary, outcome: result[:outcome].to_s,
                         account_id: account&.id, person: account&.person&.identity_summary }
        else
          # Keep redeeming outstanding links issued before the unified-table
          # transition. The legacy service enforces the same verified exact
          # email requirement and retires only a disposable signup placeholder.
          invitation = PersonAccountInvitationService.redeem!(raw_token: raw_token, user: Current.user)
          account = Current.user.reload.account
          render json: { invitation: invitation.summary, outcome: "linked",
                         account_id: account&.id, person: account&.person&.identity_summary }
        end
      rescue ClaimInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue PersonAccountInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def set_person
        @person = Person.canonical.find(params[:person_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Person not found" }, status: :not_found
      end

      def set_invitation
        @invitation = ClaimInvitation.find_by(id: params[:id], claimable_type: "Person")
        render json: { error: "Invitation not found" }, status: :not_found unless @invitation
      end

      def person_owner?
        Current.user.admin? || Current.user.coach?
      end
    end
  end
end
