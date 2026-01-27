# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

gem "dotenv-rails", "~> 3.2"

gem "paranoia", "~> 3.1"

# WebSocket client for connecting to Nostr relays
gem "faye-websocket", "~> 0.12"
gem "eventmachine", "~> 1.2"

# Service object infrastructure
gem "dry-types", "~> 1.7"
gem "dry-initializer", "~> 3.1"
gem "dry-struct", "~> 1.6"
gem "dry-initializer-rails", "~> 3.1"
gem "dry-monads", "~> 1.6"
gem "dry-validation", "~> 1.10"

# NIP-01: Nostr protocol and Schnorr signature verification (BIP-340)
gem "nostr", "~> 0.7"

# Thread-safe data structures for WebSocket connections
gem "concurrent-ruby", "~> 1.2"

# Redis for cross-worker pub/sub (enables Puma clustered mode)
gem "redis", "~> 5.0"
gem "connection_pool", "~> 2.4"

# NIP-50: OpenSearch for full-text search
gem "opensearch-ruby", "~> 3.0"

gem "barnes", "~> 0.0.9"
