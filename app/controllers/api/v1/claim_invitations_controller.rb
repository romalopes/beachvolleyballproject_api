module Api
  module V1
    # One-time invitations for any claimable subject: a player profile, a coach
    # profile, or a Person with no account. Replaces the two parallel
    # controllers this unified; both remain routed for one release.
    #
    # Raw tokens are returned only by create and are never serialized from the
    # model. Redemption accepts the invitation and links the signed-in account;
    # recipient-email invitations additionally require a verified exact match.
    class ClaimInvitationsController < ApplicationController
      include ContentAuthorization
      include Pagination

      rate_limit to: 10, within: 1.minute, only: :create
      rate_limit to: 20, within: 1.minute, only: :redeem

      before_action :require_authentication
      before_action :require_claim_invitation_manager!, only: %i[index create revoke]
      before_action :set_invitation, only: %i[show revoke accept decline]

      def index
        return management_index if params[:management].present?

        if params[:claimable_type].blank? && params[:claimable_id].blank?
          invitations = if Current.user.admin?
            ClaimInvitation.all
          elsif Current.user.curator?
            ClaimInvitation.includes(:claimable).order(created_at: :desc).limit(200)
              .select { |invitation| subject_owner?(invitation.claimable) }
          else
            ClaimInvitation.where(invited_by: Current.user)
          end
          rows = invitations.is_a?(Array) ? invitations : invitations.order(created_at: :desc).limit(200).to_a
          return render json: rows.map(&:summary)
        end
        return render json: { error: "Claimable not found" }, status: :not_found unless subject
        return render json: { error: "Claimable not found" }, status: :not_found unless subject_owner?

        render json: subject.claim_invitations.order(created_at: :desc).map(&:summary)
      end

      def claimables
        user = Current.user
        return render json: { error: "Profile manager access is required" }, status: :forbidden unless user.admin? || user.curator? || user.coach?

        type = params[:claimable_type].presence || "all"
        return render json: { error: "Unsupported profile type" }, status: :unprocessable_entity unless %w[all PlayerProfile CoachProfile].include?(type)
        status_filter = params[:status].presence || "active"
        return render json: { error: "Invalid profile status" }, status: :unprocessable_entity unless %w[all active archived].include?(status_filter)
        link_filter = params[:link_state].presence || "all"
        return render json: { error: "Invalid profile link state" }, status: :unprocessable_entity unless %w[all linked unlinked].include?(link_filter)

        relations = type == "all" ? [ PlayerProfile, CoachProfile ] : [ type.constantize ]
        records = relations.flat_map do |klass|
          relation = ProfileManagementScope.scope(klass.all, user: user)
          relation = relation.where(status: status_filter) unless status_filter == "all"
          if link_filter == "linked"
            relation = relation.where.not(account_id: nil)
          elsif link_filter == "unlinked"
            relation = relation.where(account_id: nil)
          end
          if params[:q].present?
            term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            relation = relation.where("#{klass.table_name}.display_name ILIKE :term", term: term)
          end
          relation.order(:id).to_a.map do |profile|
            can_invite = ProfilePolicy.new(actor: user, profile: profile).invite? && ClaimSubject.for(profile).eligible?
            {
              claimable_type: klass.name,
              claimable_id: profile.id,
              display_name: profile.full_name,
              status: profile.status,
              linked_to_account: profile.account_id.present?,
              can_invite: can_invite
            }
          end
        end
        records.sort_by! { |row| [ row[:display_name].to_s.downcase, row[:claimable_type], row[:claimable_id] ] }
        page_records = records.slice((page_param - 1) * per_page_param, per_page_param) || []
        render json: { data: page_records, meta: pagination_meta(records.length) }
      end

      def create
        return render json: { error: "Claimable not found" }, status: :not_found unless subject
        return render json: { error: "Claimable not found" }, status: :not_found unless subject_owner?

        invitation, raw_token = ClaimInvitationService.issue!(
          claimable: subject,
          invited_by: Current.user,
          invitee_email: invitation_email
        )
        # Record delivery for audit/reporting. Linking is decided from an exact
        # verified-email match, whether the recipient got a mail or a copied URL.
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

      def received
        return render json: { error: ClaimInvitationService::VERIFICATION_MESSAGE }, status: :forbidden unless Current.user.email_verified?

        invitations = ClaimInvitation.where(invitee_email: Current.user.email_address)
          .order(created_at: :desc).limit(100)
        render json: invitations.map(&:summary)
      end

      def accept
        result = ClaimInvitationService.accept_received!(invitation: @invitation, user: Current.user)
        render json: redeem_payload(result), status: :created
      rescue ClaimInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def decline
        result = ClaimInvitationService.decline_received!(invitation: @invitation, user: Current.user)
        render json: result[:invitation].summary
      rescue ClaimInvitationService::InvitationError => e
        render json: { error: e.message }, status: :unprocessable_entity
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

      def management_index
        user = Current.user
        return render json: { error: "Profile manager access is required" }, status: :forbidden unless user.admin? || user.curator? || user.coach?

        invitations = if user.admin? || user.curator?
          ClaimInvitation.all
        else
          player_ids = PlayerProfile.owned_by(user).select(:id)
          coach_ids = CoachProfile.owned_by(user).select(:id)
          ClaimInvitation.where(invited_by: user).or(
            ClaimInvitation.where(claimable_type: "PlayerProfile", claimable_id: player_ids)
              .or(ClaimInvitation.where(claimable_type: "CoachProfile", claimable_id: coach_ids))
          )
        end
        if params[:status].present? && params[:status] != "all"
          return render json: { error: "Invalid invitation status" }, status: :unprocessable_entity unless ClaimInvitation::STATUSES.include?(params[:status])
          invitations = case params[:status]
          when "active" then invitations.where(status: "active").where("expires_at > ?", Time.current)
          when "expired" then invitations.where(status: "expired").or(invitations.where(status: "active").where("expires_at <= ?", Time.current))
          else invitations.where(status: params[:status])
          end
        end
        if params[:claimable_type].present? && params[:claimable_type] != "all"
          return render json: { error: "Unsupported profile type" }, status: :unprocessable_entity unless ClaimInvitation::SUBJECT_TYPES.include?(params[:claimable_type])
          invitations = invitations.where(claimable_type: params[:claimable_type])
        end
        invitations = invitations.order(created_at: :desc)
        records, meta = paginate(invitations)
      render json: { data: records.map { |invitation| invitation.summary(include_claimable_name: true) }, meta: meta }
      end

      def pagination_meta(total)
        { page: page_param, per_page: per_page_param, total: total,
          total_pages: total.zero? ? 0 : (total.to_f / per_page_param).ceil }
      end

      def require_claim_invitation_manager!
        return if Current.user&.admin? || Current.user&.curator? || Current.user&.coach?

        render_unauthorized_or_forbidden
      end

      # The unified invitation workflow always links on redemption. The
      # pending-review shape remains for the separate manual profile-claim flow.
      def redeem_payload(result)
        payload = { invitation: result[:invitation].summary, outcome: result[:outcome].to_s }
        if result[:outcome] == :linked
          payload[:account_id] = Current.user.reload.account&.id
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

      # Profile invitations remain creator-owned. A Person is a club record and
      # may be invited by any authorized content creator, as in the legacy
      # Person-account invitation workflow.
      def subject_owner?(record = subject)
        return false if record.nil?
        return Current.user.admin? || Current.user.coach? if record.is_a?(Person)
        return Current.user.admin? unless record.respond_to?(:created_by_id)

        ProfilePolicy.new(actor: Current.user, profile: record).invite?
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
