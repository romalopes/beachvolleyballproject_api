module Api
  module V1
    # Invitations for connecting an Account to an already-recorded Person.
    # PlayerClaimInvitations remain a separate workflow for claiming a
    # PlayerProfile that has no Person yet.
    class PersonAccountInvitationsController < ApplicationController
      include ContentAuthorization

      rate_limit to: 10, within: 1.minute, only: :create
      rate_limit to: 20, within: 1.minute, only: :redeem

      before_action :require_authentication
      before_action :require_content_creator!, except: :redeem
      before_action :set_person, only: %i[index create]
      before_action :set_invitation, only: :revoke

      def index
        render json: @person.person_account_invitations.order(created_at: :desc).map(&:summary)
      end

      def create
        invitation, raw_token = PersonAccountInvitationService.issue!(person: @person, invited_by: Current.user)
        delivered = PersonAccountInvitationDelivery.deliver(invitation: invitation, raw_token: raw_token)

        render json: { invitation: invitation.summary, token: raw_token, email_delivered: delivered }, status: :created
      rescue PersonAccountInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def revoke
        invitation = PersonAccountInvitationService.revoke!(invitation: @invitation)
        render json: invitation.summary
      rescue PersonAccountInvitationService::InvitationError => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def redeem
        invitation = PersonAccountInvitationService.redeem!(raw_token: params[:token].to_s, user: Current.user)
        account = Current.user.reload.account
        render json: {
          invitation: invitation.summary,
          account_id: account.id,
          person: account.person.identity_summary
        }
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
        @invitation = PersonAccountInvitation.find_by(id: params[:id])
        render json: { error: "Invitation not found" }, status: :not_found unless @invitation
      end
    end
  end
end
