module Api
  module V1
    # Health probes for the React SPA's API Health diagnostics page.
    #
    # GET /api/v1/health          — public liveness check (no auth, no
    #                               version/env/stack details exposed).
    # GET /api/v1/health/detailed — admin-only diagnostics: infrastructure
    #                               info plus record counts for the domain
    #                               resources the SPA consumes.
    class HealthController < ApplicationController
      before_action :authorize_admin!, only: :detailed

      def index
        if database_connected?
          render json: { status: "ok" }
        else
          render json: { status: "error" }, status: :service_unavailable
        end
      end

      def detailed
        db_ok = database_connected?
        payload = {
          status: db_ok ? "ok" : "error",
          service: "bvb-api",
          database: db_ok ? "ok" : "error",
          environment: Rails.env,
          version: backend_version,
          timestamp: Time.current.utc.iso8601,
          database_details: db_connection_info,
          server: server_info,
          endpoint: endpoint_info,
          counts: record_counts
        }
        render json: payload, status: db_ok ? :ok : :service_unavailable
      end

      private

      # Backend version. Prefers the value set on the Rails Application config
      # in config/application.rb (freshly booted process), then the
      # BACK_END_VERSION constant, then "unknown". On a long-running dev server
      # that predates config/application.rb / the app_version initializer (or
      # that hot-reloaded controllers but never re-ran those boot files), the
      # config key and/or constant may be absent, so we load the version file on
      # demand. Every read path is rescued/guarded so the endpoint can never 500
      # on a missing version.
      def backend_version
        version = health_config_version
        if version.blank?
          load_backend_version_constant unless defined?(BACK_END_VERSION)
          version = BACK_END_VERSION if defined?(BACK_END_VERSION)
        end
        version.presence || "unknown"
      end

      def health_config_version
        Rails.application.config.health_version
      rescue StandardError
        nil
      end

      # config/initializers/app_version.rb only defines the constant and logs,
      # so it is safe to require on demand from a long-running (stale) process.
      def load_backend_version_constant
        file = Rails.root.join("config/initializers/app_version.rb")
        require file if file.exist?
      rescue StandardError
        nil
      end

      def database_connected?
        ActiveRecord::Base.connection.active?
      rescue StandardError
        false
      end

      # Live connection details without ever exposing secrets. Each accessor
      # is resolved defensively (UrlConfig from DATABASE_URL does not expose
      # every field, e.g. #port) so the endpoint can never 500 — admins still
      # get server/endpoint info when the DB is down.
      def db_connection_info
        config = ActiveRecord::Base.connection_db_config
        pool = ActiveRecord::Base.connection_pool
        {
          adapter: db_config_value(config, :adapter),
          database: db_config_value(config, :database),
          host: db_config_value(config, :host),
          port: db_config_value(config, :port),
          username: db_config_value(config, :username),
          encoding: db_config_value(config, :encoding),
          pool: safe_pool_value(pool, :size),
          checkout_timeout: safe_pool_value(pool, :checkout_timeout),
          reaping_frequency: reaper_frequency,
          idle_timeout: safe_pool_value(pool, :idle_timeout)
        }
      rescue StandardError
        {
          adapter: nil, database: nil, host: nil, port: nil, username: nil,
          encoding: nil, pool: nil, checkout_timeout: nil,
          reaping_frequency: nil, idle_timeout: nil
        }
      end

      def db_config_value(config, key)
        config.public_send(key)
      rescue NoMethodError
        nil
      end

      def safe_pool_value(pool, key)
        return nil unless pool

        pool.public_send(key)
      rescue NoMethodError
        nil
      end

      def reaper_frequency
        reaper = ActiveRecord::Base.connection_pool&.reaper
        return nil unless reaper&.respond_to?(:frequency)

        reaper.frequency
      rescue StandardError
        nil
      end

      def server_info
        {
          rails_version: Rails.version,
          ruby: RUBY_DESCRIPTION,
          puma_workers: puma_worker_count,
          hostname: (Socket.gethostname rescue nil),
          pid: Process.pid
        }
      end

      def endpoint_info
        {
          scheme: request.scheme,
          host: request.host,
          port: request.port,
          base_url: request.base_url,
          path: request.path
        }
      end

      # Record counts for the domain resources the React SPA consumes, plus
      # users so admins can sanity-check role/seed state. A table that
      # disappears (e.g. pending migration) reports 0 instead of 500ing.
      def record_counts
        {
          categories: safe_count(Category),
          skills: safe_count(Skill),
          drills: safe_count(Drill),
          drill_skills: safe_count(DrillSkill),
          media_assets: safe_count(MediaAsset),
          training_sessions: safe_count(TrainingSession),
          users: safe_count(User)
        }
      end

      def safe_count(model)
        model.count
      rescue StandardError
        0
      end

      # Puma exposes a `workers` accessor when running in clustered mode. In
      # the default single-process dev setup it returns 0, which is exactly
      # what we want to surface ("0 workers" = single process).
      def puma_worker_count
        if defined?(Puma) && Puma.respond_to?(:stats) && (stats = Puma.stats).is_a?(String)
          stats[/\A\{.*?"workers":\s*(\d+)/, 1]&.to_i
        end
      rescue StandardError
        nil
      end
    end
  end
end
