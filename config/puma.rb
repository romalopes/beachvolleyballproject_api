# Workaround for macOS fork-safety crash with Objective-C runtime
# See: https://github.com/puma/puma/issues/2462
ENV["OBJC_DISABLE_INITIALIZE_FORK_SAFETY"] = "YES" if RUBY_PLATFORM =~ /darwin/

# Puma configuration for SSL
ssl_bind "127.0.0.1", "3001",
  key: "config/ssl/localhost.key",
  cert: "config/ssl/localhost.crt"

environment ENV.fetch("RAILS_ENV") { "development" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Single-mode in development to avoid fork-related crashes on macOS;
# use cluster mode with multiple workers in production for throughput.
worker_count = ENV.fetch("WEB_CONCURRENCY", ENV.fetch("RAILS_ENV", "development") == "production" ? "2" : "0").to_i
workers worker_count
preload_app! if worker_count.positive?

plugin :tmp_restart
