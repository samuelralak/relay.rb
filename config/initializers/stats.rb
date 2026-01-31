# frozen_string_literal: true

# Stats Dashboard Configuration
# Configure the Stats engine for monitoring relay metrics

Stats.configure do |config|
  # Dashboard title displayed in the header
  # Default: "Relay Stats"
  config.dashboard_title = ENV.fetch("STATS_DASHBOARD_TITLE", "Relay Stats")

  # Enable authentication for the stats dashboard
  # When enabled, users must provide a valid API key to access the dashboard
  # Default: false (public access)
  config.authentication_enabled = ENV.fetch("STATS_AUTH_ENABLED", "false") == "true"
end
