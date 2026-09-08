#!/usr/bin/env bash
set -o errexit

# Render build script for beachvolleyballproject_api
# Installs dependencies, precompiles assets, and runs migrations for all databases.

bundle install

# Precompile assets (SECRET_KEY_BASE_DUMMY=1 skips key validation during build)
SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Run primary + secondary database migrations
# cache / queue / cable all share the same DATABASE_URL so tables go into the same PG database
./bin/rails db:migrate
./bin/rails db:migrate:cache
./bin/rails db:migrate:queue
./bin/rails db:migrate:cable