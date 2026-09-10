module Api
  module V1
    module Admin
      # Serves the tail of the application's Rails log file (admin-only).
      class SystemLogsController < ApplicationController
        before_action :authorize_admin!

        MAX_LINES = 5000

        # GET /api/v1/admin/system_logs?lines=500
        def index
          lines = (params[:lines] || 500).to_i.clamp(1, MAX_LINES)
          render json: { lines: read_log_tail(lines) }
        end

        private

        def log_path
          Rails.root.join("log", "#{Rails.env}.log").to_s
        end

        def read_log_tail(count)
          return [] unless File.exist?(log_path)

          # Sliding window: keeps only the last `count` lines in memory.
          window = []
          File.foreach(log_path) do |line|
            window << line
            window.shift if window.size > count
          end
          window
        rescue StandardError => e
          Rails.logger.error("SystemLogsController failed to read log: #{e.message}")
          []
        end
      end
    end
  end
end