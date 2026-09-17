# Single source of truth for the application version (mirrors
# config.health_version set in config/application.rb). Override per deploy
# with APP_VERSION. Logged at boot so the served version is always
# visible and "unknown" cannot slip in silently.
APP_VERSION = ENV["APP_VERSION"].presence || "0.0.21"

Rails.logger.info("bvb-api version: #{APP_VERSION}") if Rails.logger
