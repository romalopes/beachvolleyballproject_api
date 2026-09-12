module Api
  module V1
    module Admin
      # Admin "Act as User" impersonation. Lets an admin temporarily operate
      # as another (non-admin) user. State is kept on the admin's own session
      # (cookie value + sessions.impersonated_user_id column) so it works for
      # both server-rendered and bearer-token API requests.
      class ImpersonationsController < ApplicationController
        before_action :authorize_admin!

        # POST /api/v1/admin/impersonations { user_id: 123 }
        def create
          target = User.find_by(id: params[:user_id])

          if target.nil?
            return render json: { error: "User not found." }, status: :not_found
          end
          if impersonating?
            return render json: { error: "Already impersonating a user. Stop impersonation first." },
                          status: :unprocessable_entity
          end
          if target == real_current_user
            return render json: { error: "You cannot impersonate yourself." },
                          status: :unprocessable_entity
          end
          if target.admin?
            return render json: { error: "Impersonating another admin is not allowed." },
                          status: :unprocessable_entity
          end

          start_impersonating(target)
          log_impersonation("started acting as", target)
          render json: impersonation_payload(target), status: :created
        end

        # DELETE /api/v1/admin/impersonations
        def destroy
          unless impersonating?
            return render json: { error: "Not currently impersonating." },
                          status: :unprocessable_entity
          end

          target = Current.impersonated_user
          stop_impersonating
          log_impersonation("stopped acting as", target)
          render json: impersonation_payload(nil)
        end

        private

        def impersonation_payload(target)
          {
            impersonating: !target.nil?,
            effective_user: target && {
              id: target.id,
              name: target.name,
              email_address: target.email_address,
              roles: target.roles.pluck(:name)
            },
            real_admin: {
              id: real_current_user.id,
              name: real_current_user.name,
              email_address: real_current_user.email_address
            }
          }
        end

        # Audit: the real admin is always the log's actor (user:) while the
        # impersonated user is attached as a polymorphic object, so the trail
        # distinguishes "Actor: Alice (Admin)" from "Effective user: John".
        def log_impersonation(verb, target)
          LogService.log(
            description: "Admin #{real_current_user.name} #{verb} #{target.name}",
            action: "impersonate",
            method: request.request_method,
            user: real_current_user,
            path: request.path,
            request_id: request.request_id,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            status: response.status,
            objects: [target]
          )
        rescue StandardError => e
          Rails.logger.error("Impersonation logging failed: #{e.message}")
        end
      end
    end
  end
end
