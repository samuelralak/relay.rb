# frozen_string_literal: true

# Automatic database role switching for read replicas
#
# When DATABASE_REPLICA_URL is configured, Rails will automatically:
# - Use the primary (writer) database for POST, PUT, PATCH, DELETE requests
# - Use the replica (reader) database for GET and HEAD requests
# - Wait 2 seconds after a write before switching to replica (replication lag buffer)
#
# This middleware is only enabled when a replica is configured.

if ENV["DATABASE_REPLICA_URL"].present?
  Rails.application.configure do
    # Delay before switching to replica after a write (handles replication lag)
    config.active_record.database_selector = { delay: 2.seconds }

    # Resolver determines which database to use based on request
    config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver

    # Context stores the timestamp of last write (uses session by default)
    config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
  end
end
