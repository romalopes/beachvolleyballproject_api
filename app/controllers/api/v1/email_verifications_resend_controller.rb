module Api
  module V1
    class EmailVerificationsResendController < ApplicationController
      allow_unauthenticated_access only: :create

      # POST /api/v1/email-verifications/resend
      #
      # Body: { "email_address": "user@example.com" }
      #
      # Returns 202 with a uniform body so the client never learns whether the
      # address exists, is already verified, or verification is disabled.
      def create
        EmailVerificationService.resend(params.fetch(:email_address, ""))
        render json: {
          status: "resent",
          email_address: params[:email_address],
          message: "If an unverified account exists for this address, a new verification email has been sent."
        }, status: :accepted
      end
    end
  end
end