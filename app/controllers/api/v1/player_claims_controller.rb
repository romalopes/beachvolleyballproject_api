module Api
  module V1
    # Authenticated players request association with an existing unlinked
    # PlayerProfile. Coaches/admins review the request; names and identity data
    # are never exposed to a claimant by a claim lookup.
    class PlayerClaimsController < ApplicationController
      include ContentAuthorization
      include Pagination

      before_action :require_authentication
      before_action :set_claim, only: %i[show approve reject cancel]

      def candidates
        account = Current.user&.account
        person = account&.person
        return render json: { error: "An active Account is required to search for profiles" }, status: :unprocessable_entity unless account && person&.status == "active"

        type = params[:claimable_type].presence || "PlayerProfile"
        return render json: { error: "Unsupported profile type" }, status: :unprocessable_entity unless ProfileClaimability::PROFILE_TYPES.include?(type)

        results, total = ProfileClaimCandidateFinder.new(account: account, user: Current.user, type: type,
          query: params[:q], organisation_id: params[:organisation_id])
          .page(page: page_param, per_page: per_page_param)
        render json: { data: results.map(&:as_json), meta: pagination_meta(total) }
      end

      def index
        if params[:management].present?
          return management_index
        end

        account = Current.user&.account
        own_claims = if account
                       PlayerClaim.where(claimant_account: account)
                         .or(PlayerClaim.where(claimant_account_id: nil, person: account.person))
                     else
                       PlayerClaim.none
                     end
        own_claims = own_claims.order(created_at: :desc)
        review_claims = if Current.user&.admin?
                          PlayerClaim.pending.order(:created_at)
        elsif Current.user&.coach?
                          # `pending_for_owner` rather than a `player_profiles:` join:
                          # the Phase 18 migration clears `player_profile_id`, so
                          # an inner join would hide every migrated claim here.
                          PlayerClaim.pending_for_owner(Current.user).order(:created_at)
        else
                          PlayerClaim.none
        end

        payloads = own_claims.to_a.map do |claim|
          can_review = claim.reviewable_by?(Current.user)
          [ claim.id, claim.summary(include_profile_name: can_review,
                                    include_review_details: can_review) ]
        end.to_h
        review_claims.each do |claim|
          payloads[claim.id] = claim.summary(include_profile_name: true, include_review_details: true)
        end
        records, meta = paginate_array(payloads.values.sort_by { |claim| claim[:created_at] || claim["created_at"] }.reverse)
        render json: { data: records, meta: meta }
      end

      def show
        return unless may_view_claim?

        can_review = reviewer?
        render json: @claim.summary(include_profile_name: can_review,
                                     include_review_details: can_review)
      end

      def create
        account = Current.user&.account
        person = account&.person
        return render_claim_error("An Account with an active identity is required to request a claim", :unprocessable_entity, "validation_failed") unless account && person&.status == "active"

        type = params[:claimable_type].presence || "PlayerProfile"
        unless ProfileClaimability::PROFILE_TYPES.include?(type)
          return render_claim_error("Profile cannot be claimed", :not_found, "not_found")
        end
        id = params[:claimable_id].presence || params[:player_profile_id]
        profile = type.constantize.find_by(id: id)
        return render_claim_error("Profile cannot be claimed", :not_found, "not_found") unless profile
        return render_claim_error("Profile cannot be claimed", :not_found, "not_found") unless ProfileClaimability.allowed?(profile: profile, user: Current.user)

        claim = PlayerClaimService.request!(
          claimable: profile,
          account: account,
          initiated_by_person: person
        )
        render json: claim.summary, status: :created
      rescue PlayerClaimService::ClaimError => e
        status = e.message == "Forbidden" ? :forbidden : :conflict
        code = status == :forbidden ? "forbidden" : "conflict"
        render_claim_error(e.message, status, code)
      rescue ActiveRecord::RecordInvalid => e
        render_claim_error(e.message, :unprocessable_entity, "validation_failed")
      rescue ActiveRecord::RecordNotUnique
        render_claim_error("Your Account already has a pending claim for this profile", :conflict, "conflict")
      end

      def approve
        return unless authorize_review!
        verification_method = params[:verification_method].to_s
        unless PlayerClaim::VERIFICATION_METHODS.include?(verification_method)
          return render_claim_error("A valid verification_method is required", :unprocessable_entity, "validation_failed")
        end

        claim = PlayerClaimService.approve!(claim: @claim, reviewer_account: Current.user.account,
                                            verification_method: verification_method)
        render json: claim.summary(include_profile_name: true, include_review_details: true)
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        status = e.message == "Forbidden" ? :forbidden : :conflict
        render_claim_error(e.message, status, status == :forbidden ? "forbidden" : "conflict")
      end

      def reject
        return unless authorize_review!

        reason = params[:rejection_reason].to_s.strip.presence
        claim = PlayerClaimService.reject!(claim: @claim, reviewer_account: Current.user.account,
                                           reason: reason)
        render json: claim.summary(include_profile_name: true, include_review_details: true)
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        status = e.message == "Forbidden" ? :forbidden : :conflict
        render_claim_error(e.message, status, status == :forbidden ? "forbidden" : "conflict")
      end

      def cancel
        return render_claim_error("Claim not found", :not_found, "not_found") unless claimant?

        claim = PlayerClaimService.cancel!(claim: @claim)
        render json: claim.summary
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        render_claim_error(e.message, :conflict, "conflict")
      end

      private

      def management_index
        user = Current.user
        return render json: { error: "Profile manager access is required" }, status: :forbidden unless user.admin? || user.curator? || user.coach?

        claims = if user.admin? || user.curator?
          PlayerClaim.all
        else
          player_ids = PlayerProfile.owned_by(user).select(:id)
          coach_ids = CoachProfile.owned_by(user).select(:id)
          PlayerClaim.where(claimable_type: "PlayerProfile", claimable_id: player_ids)
            .or(PlayerClaim.where(claimable_type: "CoachProfile", claimable_id: coach_ids))
            .or(PlayerClaim.where(claimable_type: nil, player_profile_id: player_ids))
        end
        if params[:status].present? && params[:status] != "all"
          return render json: { error: "Invalid claim status" }, status: :unprocessable_entity unless PlayerClaim::STATUSES.include?(params[:status])
          claims = claims.where(status: params[:status])
        end
        if params[:claimable_type].present? && params[:claimable_type] != "all"
          return render json: { error: "Unsupported profile type" }, status: :unprocessable_entity unless ProfileClaimability::PROFILE_TYPES.include?(params[:claimable_type])
          claims = claims.where(claimable_type: params[:claimable_type])
        end
        claims = claims.order(created_at: :desc)
        records, meta = paginate(claims)
        render json: { data: records.map { |claim|
          claim.summary(include_profile_name: true, include_review_details: claim.reviewable_by?(user)).merge(can_review: claim.reviewable_by?(user))
        }, meta: meta }
      end

      def paginate_array(records)
        total = records.length
        [ records.slice((page_param - 1) * per_page_param, per_page_param) || [],
          pagination_meta(total) ]
      end

      def pagination_meta(total)
        { page: page_param, per_page: per_page_param, total: total,
          total_pages: total.zero? ? 0 : (total.to_f / per_page_param).ceil }
      end

      def set_claim
        @claim = PlayerClaim.find_by(id: params[:id])
        render_claim_error("Claim not found", :not_found, "not_found") unless @claim
      end

      def claimant?
        account = Current.user&.account
        return account.id == @claim.claimant_account_id if account && @claim.claimant_account_id

        account&.person_id == @claim.person_id
      end

      def reviewer?
        @claim.reviewable_by?(Current.user)
      end

      def may_view_claim?
        return true if claimant? || reviewer? || ProfileManagementScope.allowed?(profile: @claim.subject, user: Current.user)

        render_claim_error("Claim not found", :not_found, "not_found")
        false
      end

      def authorize_review!
        unless Current.user&.account
          render_claim_error("A reviewer Account is required", :forbidden, "forbidden")
          return false
        end
        if claimant?
          render_claim_error("A claimant cannot review their own claim", :forbidden, "forbidden")
          return false
        end
        unless @claim.reviewable_by?(Current.user)
          render_claim_error("Forbidden", :forbidden, "forbidden")
          return false
        end

        true
      end

      def render_claim_error(message, status, code)
        render json: { error: message, code: code }, status: status
      end
    end
  end
end
