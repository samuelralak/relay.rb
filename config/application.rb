# frozen_string_literal: true

require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RelayRb
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Autoload lib/ subdirectories, excluding non-Ruby directories
    config.autoload_lib(ignore: %w[assets tasks negentropy relay_sync nostr_relay relay_search])

    # Add app/middleware to autoload paths (not included by default)
    # config.autoload_paths << Rails.root.join("app/middleware")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Add session middleware for Stats dashboard (mounted engine requires sessions)
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_relay_session"
    config.middleware.use ActionDispatch::Flash

    # Use UUID as the primary key type
    config.generators do |generator|
      generator.orm :active_record, primary_key_type: :uuid
    end
  end
end
