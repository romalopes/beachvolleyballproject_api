module Api
  module V1
    # One-time invitations for any claimable subject: a player profile, a coach
    # profile, or a Person with no account. Replaces the two parallel
    # controllers this unified; both remain routed for one release.
    #
    # Raw tokens are returned only by create and are never serialized from the
    # model. Redemption either links immediately (only when the invitation was
    # genuinely emailed to the address the recipient controls) or creates a
    # pending claim for staff review.
    class ClaimInvitationsController < ApplicationController
      include ContentAuthorization

      rate_limit to: 10, within: 1.minute, only: :create
      rate_limit to: 20, within: 1.minute, only: :redeem

      before_action :require_authentication
      before_action :require_content_creator!, only: %i[index create revoke]
      before_action :set_invitation, only: %i[show revoke]

      def index
        return render json: { error: "Claimable not found" }, status: :not_found unless subject
        return render json: { error: "Claimable not found" }, status: :not_found unless subject_owner?

        render json: subject.claim_invitations.order(created_at: :desc).map(&:summary)
      end

      def create
        return render json: { error: "Claimable not found" }, status: :not_found unless subject
        return render json: { error: "Claimable not found" }, status: :not_found unless subject_owner?

        invitation, raw_token = ClaimInvitationService.issue!(
          claimable: subject,
          invited_by: Current.user,
          invitee_email: invitation_email
        )
        # Recording that the club really sent the message is what later lets the
        # invitation auto-approve; a link copied by hand cannot.
        delivered = ClaimInvitationDelivery.deliver(invitation: invitation, raw_token: raw_token)
        ClaimInvitationService.mark_emailed!(invitation: invitation) if delivered

        render json: {
          invitation: invitation.reload.summary,
          token: raw_token,
          email_delivered: delivered
        }, status: :created
      rescue ClaimInvitationService::InvitationError, ClaimSubject::Ineligible,
             ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def redeem
        result = ClaimInvitationService.redeem!(raw_token: params[:token].to_s, user: Current.user)

        render json: redeem_payload(result), status: :created
      rescue ClaimInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def show
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?

        render json: @invitation.summary
      end

      def revoke
        return render json: { error: "Invitation not found" }, status: :not_found unless invitation_owner?

        invitation = ClaimInvitationService.revoke!(invitation: @invitation)
        render json: invitation.summary
      rescue ClaimInvitationService::InvitationError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      private

      # Two shapes, so the SPA can tell "you are linked now" from "a coach has
      # to look at this".
      def redeem_payload(result)
        payload = { invitation: result[:invitation].summary, outcome: result[:outcome].to_s }
        if result[:outcome] == :linked
          payload[:person] = Current.user.reload.person&.identity_summary
        else
          payload[:claim] = result[:claim].summary
          payload[:message] =
            "Your request was sent for review. A coach or administrator will approve it."
        end
        payload
      end

      def subject
        return @subject if defined?(@subject)

        @subject = begin
          type = params[:claimable_type].to_s
          klass = ClaimInvitation::SUBJECT_TYPES.include?(type) ? type.safe_constantize : nil
          klass&.find_by(id: params[:claimable_id])
        end
      end

      def set_invitation
        @invitation = ClaimInvitation.find_by(id: params[:id])
        render json: { error: "Invitation not found" }, status: :not_found unless @invitation
      end

      def invitation_email
        value = params[:invitee_email]
        return nil if value.nil?

        value.to_s.strip.presence
      end

      # Mirrors the legacy `profile_owner?`: an admin, or the coach who recorded
      # the profile. A Person subject has no `created_by`, so only an admin may
      # issue those.
      def subject_owner?(record = subject)
        return false if record.nil?
        return Current.user.admin? unless record.respond_to?(:created_by_id)

        Current.user.admin? || (Current.user.coach? && record.created_by_id == Current.user.id)
      end

      # Resolved from the invitation rather than the request params: the member
      # `show`/`revoke` actions carry only an id, so there is no claimable to
      # read ownership from.
      def invitation_owner?
        return true if Current.user.admin?

        subject_owner?(@invitation&.claimable)
      end

      def invalid_invitation
        render json: { error: ClaimInvitationService::INVALID_MESSAGE }, status: :unprocessable_entity
      end
    end
  end
end
