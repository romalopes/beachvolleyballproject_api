module Api
  module V1
    module Admin
      class LogsController < ApplicationController
        before_action :authorize_admin!

        def index
          logs = Log.includes(:user, :log_objects).order(created_at: :desc, id: :desc)

          # NOTE: `params[:action]` is reserved by Rails routing (it is "index"/"show"),
          # so the audit-action filter must be read from the query string instead.
          action_value = request.query_parameters[:action].presence || params[:action_filter].presence
          logs = logs.for_action(action_value) if action_value.present?
          logs = logs.for_user(params[:user_id]) if params[:user_id].present?
          logs = logs.for_request(params[:request_id]) if params[:request_id].present?

          if params[:object_type].present? || params[:object_id].present?
            conditions = {}
            conditions[:object_type] = params[:object_type] if params[:object_type].present?
            conditions[:object_id] = params[:object_id] if params[:object_id].present?
            logs = logs.joins(:log_objects).where(log_objects: conditions).distinct
          end

          logs = apply_date_filter(logs)
          logs = apply_search_filter(logs)

          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 25).to_i.clamp(1, 100)
          total = logs.distinct.count(:id)
          logs = logs.offset((page - 1) * per_page).limit(per_page)

          render json: {
            data: logs.map { |log| serialize_log(log) },
            meta: {
              page: page,
              per_page: per_page,
              total: total,
              total_pages: (total.to_f / per_page).ceil
            }
          }
        end

        def show
          log = Log.includes(:user, :log_objects).find(params[:id])
          render json: { data: serialize_log(log, detail: true) }
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Log not found" }, status: :not_found
        end

        private

        def apply_date_filter(scope)
          start_value = params[:date_from].presence || params[:start_date].presence
          end_value = params[:date_to].presence || params[:end_date].presence
          from = parse_date(start_value)
          to = parse_date(end_value)
          scope = scope.where("logs.created_at >= ?", from.beginning_of_day) if from
          scope = scope.where("logs.created_at <= ?", to.end_of_day) if to
          scope
        end

        def apply_search_filter(scope)
          return scope if params[:search].blank?

          pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:search].to_s.strip)}%"
          scope.where(
            "logs.description ILIKE ? OR logs.action ILIKE ? OR logs.path ILIKE ?",
            pattern, pattern, pattern
          )
        end

        def parse_date(value)
          return nil if value.blank?

          Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def serialize_log(log, detail: false)
          result = {
            id: log.id,
            description: log.description,
            action: log.action,
            method: log.method,
            path: log.path,
            status: log.status,
            user: log.user ? { id: log.user.id, name: log.user.name, email_address: log.user.email_address } : nil,
            created_at: log.created_at.iso8601
          }

          if detail
            result[:ip_address] = log.ip_address
            result[:user_agent] = log.user_agent
            result[:request_id] = log.request_id
            result[:objects] = log.log_objects.map { |lo| serialize_log_object(lo, detail: true) }
          else
            result[:objects] = log.log_objects.map { |lo| serialize_log_object(lo, detail: false) }
          end

          result
        end

        def serialize_log_object(lo, detail: false)
          obj = lo.object
          result = {
            type: lo.object_type,
            id: lo.object_id
          }

          if detail
            result[:label] = obj ? LogService.human_label(obj) : nil
            result[:exists] = obj.present?
            result[:slug] = obj.slug if obj&.respond_to?(:slug)
          end

          result
        end
      end
    end
  end
end