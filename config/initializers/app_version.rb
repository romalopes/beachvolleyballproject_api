# Single source of truth for the backend version reported by
# GET /api/v1/health/detailed. Override per deploy with BACK_END_VERSION
# (the frontend mirrors this in src/constants/versions.ts).
BACK_END_VERSION = ENV["BACK_END_VERSION"].presence || "0.0.1"
