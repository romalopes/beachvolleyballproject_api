# Shared constant for the backend version (mirrors
# config.health_version set in config/application.rb). Override per deploy
# with BACK_END_VERSION. Logged at boot so the served version is always
# visible and "unknown" cannot slip in silently.
BACK_END_VERSION = ENV["BACK_END_VERSION"].presence || "0.0.1"

Rails.logger.info("bvb-api version: #{BACK_END_VERSION}") if Rails.logger
