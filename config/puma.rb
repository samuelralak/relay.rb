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
    Barnes.start
  end
end

# Enable workers in production for better concurrency
workers ENV.fetch("WEB_CONCURRENCY", 2) if ENV["RAILS_ENV"] == "production"

# Preload app for faster worker boot (copy-on-write memory savings)
preload_app! if ENV["RAILS_ENV"] == "production"

# Re-establish database connections in workers after fork
# Required when using preload_app! since master's connections don't work in workers
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
end

# Graceful shutdown for WebSocket connections
# Ensures clean dyno restarts on Heroku (prevents R12 exit timeout)

# Called when a worker process is shutting down (clustered mode)
on_worker_shutdown do
  if defined?(NostrRelay::Subscriptions)
    NostrRelay::Subscriptions.shutdown
  end
end

# Fallback: at_exit runs when process terminates (covers SIGTERM in single mode)
at_exit do
  if defined?(NostrRelay::Subscriptions) && NostrRelay::Subscriptions.connection_count > 0
    NostrRelay::Subscriptions.shutdown
  end
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
