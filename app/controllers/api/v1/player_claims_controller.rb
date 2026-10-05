module Api
  module V1
    # Authenticated players request association with an existing unlinked
    # PlayerProfile. Coaches/admins review the request; names and identity data
    # are never exposed to a claimant by a claim lookup.
    class PlayerClaimsController < ApplicationController
      include ContentAuthorization

      before_action :require_authentication
      before_action :require_content_creator!, only: %i[approve reject]
      before_action :set_claim, only: %i[show approve reject cancel]

      def candidates
        person = Current.user&.person
        return render json: { error: "A linked Person is required to search for profiles" }, status: :unprocessable_entity unless person&.status == "active"

        type = params[:claimable_type].presence || "PlayerProfile"
        return render json: { error: "Unsupported profile type" }, status: :unprocessable_entity unless ProfileClaimability::PROFILE_TYPES.include?(type)

        results = ProfileClaimCandidateFinder.new(person: person, user: Current.user, type: type).matches
        render json: results.map(&:as_json)
      end

      def index
        own_claims = PlayerClaim.where(person: Current.user&.person).order(created_at: :desc)
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

        payloads = own_claims.map do |claim|
          [ claim.id, claim.summary(include_profile_name: claim.reviewable_by?(Current.user)) ]
        end.to_h
        review_claims.each { |claim| payloads[claim.id] = claim.summary(include_profile_name: true) }
        render json: payloads.values
      end

      def show
        return unless may_view_claim?

        render json: @claim.summary(include_profile_name: reviewer?)
      end

      def create
        person = Current.user&.person
        return render json: { error: "A linked Person is required to request a claim" }, status: :unprocessable_entity unless person

        type = params[:claimable_type].presence || "PlayerProfile"
        unless ProfileClaimability::PROFILE_TYPES.include?(type)
          return render json: { error: "Profile cannot be claimed" }, status: :not_found
        end
        id = params[:claimable_id].presence || params[:player_profile_id]
        profile = type.constantize.find_by(id: id)
        return render json: { error: "Profile cannot be claimed" }, status: :not_found unless profile
        return render json: { error: "Profile cannot be claimed" }, status: :not_found unless ProfileClaimability.allowed?(profile: profile, user: Current.user)

        claim = PlayerClaimService.request!(
          claimable: profile,
          person: person,
          initiated_by_person: person
        )
        render json: claim.summary, status: :created
      rescue PlayerClaimService::ClaimError => e
        render json: { errors: [ e.message ] }, status: :conflict
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: [ "A pending claim already exists for this profile" ] }, status: :conflict
      end

      def approve
        return unless authorize_review!

        claim = PlayerClaimService.approve!(claim: @claim, reviewer: Current.user.person)
        render json: claim.summary(include_profile_name: true)
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def reject
        return unless authorize_review!

        reason = params[:rejection_reason].to_s.strip
        return render json: { errors: [ "rejection_reason is required" ] }, status: :unprocessable_entity if reason.blank?

        claim = PlayerClaimService.reject!(claim: @claim, reviewer: Current.user.person, reason: reason)
        render json: claim.summary(include_profile_name: true)
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      def cancel
        return render json: { error: "Claim not found" }, status: :not_found unless claimant?

        claim = PlayerClaimService.cancel!(claim: @claim)
        render json: claim.summary
      rescue PlayerClaimService::ClaimError, ActiveRecord::RecordInvalid => e
        render json: { errors: [ e.message ] }, status: :conflict
      end

      private

      def set_claim
        @claim = PlayerClaim.find_by(id: params[:id])
        render json: { error: "Claim not found" }, status: :not_found unless @claim
      end

      def claimant?
        Current.user&.person&.id == @claim.person_id
      end

      def reviewer?
        @claim.reviewable_by?(Current.user)
      end

      def may_view_claim?
        return true if claimant? || reviewer?

        render json: { error: "Claim not found" }, status: :not_found
        false
      end

      def authorize_review!
        unless Current.user&.person
          render json: { error: "A linked reviewer Person is required" }, status: :unprocessable_entity
          return false
        end
        if claimant?
          render json: { error: "A claimant cannot review their own claim" }, status: :forbidden
          return false
        end
        unless @claim.reviewable_by?(Current.user)
          render json: { error: "Forbidden" }, status: :forbidden
          return false
        end

        true
      end
    end
  end
end
