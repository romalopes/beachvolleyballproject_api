# Puma configuration for SSL
ssl_bind "127.0.0.1", "3001",
  key: "config/ssl/localhost.key",
  cert: "config/ssl/localhost.crt"

environment ENV.fetch("RAILS_ENV") { "development" }

pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

workers ENV.fetch("WEB_CONCURRENCY") { 2 }

preload_app!

plugin :tmp_restart
