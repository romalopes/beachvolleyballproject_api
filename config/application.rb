require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BeachvolleyballprojectApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Application version surfaced by GET /api/v1/health and
    # /api/v1/health/detailed. Kept on the Application config object so it is
    # always present at request time, independent of initializer/eager-load
    # ordering. The React app mirrors this in
    # beachvolleyballproject/src/constants/versions.ts (APP_VERSION) and the
    # "Backend Version Matches APP_VERSION" health check flags drift.
    config.health_version = ENV["APP_VERSION"].presence || "0.0.21"
  end
end
