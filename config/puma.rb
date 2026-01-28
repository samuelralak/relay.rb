# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Heroku requires ≥90s idle timeout to avoid race conditions with router keep-alive
# See: https://devcenter.heroku.com/articles/http-routing#timeouts
persistent_timeout ENV.fetch("PUMA_PERSISTENT_TIMEOUT", 90).to_i
first_data_timeout ENV.fetch("PUMA_FIRST_DATA_TIMEOUT", 30).to_i

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

if ENV["RAILS_ENV"] == "production"
  require "barnes"

  before_fork do
    ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord::Base)
    Barnes.start
  end
end

# Clustered mode with Redis pub/sub for cross-worker broadcasts
# =============================================================
# Each worker maintains its own WebSocket connections. Redis pub/sub
# synchronizes event broadcasts across workers so all connected clients
# receive events regardless of which worker they're connected to.
if ENV["RAILS_ENV"] == "production" && ENV["REDIS_URL"]
  workers ENV.fetch("WEB_CONCURRENCY", 2)
  preload_app!

  # Force workers to shutdown after 20s (Heroku gives 30s total)
  # Critical for WebSocket apps - without it, workers wait forever for connections
  worker_shutdown_timeout 20

  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
    NostrRelay::Lifecycle.on_worker_boot if defined?(NostrRelay::Lifecycle)
  end

  on_worker_shutdown do
    NostrRelay::Lifecycle.on_shutdown if defined?(NostrRelay::Lifecycle)
  end
end

# Graceful shutdown (single-process mode fallback or development)
at_exit do
  NostrRelay::Lifecycle.on_shutdown if defined?(NostrRelay::Lifecycle)
end

# Also handle lowlevel_error_handler for unexpected errors
lowlevel_error_handler do |error, env, status_code|
  if defined?(Rails)
    Rails.logger.error("[Puma] Low-level error: #{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace&.first(10)&.join("\n"))
  end
  # Return a basic error response
  [status_code, {}, ["Internal Server Error"]]
end
