# frozen_string_literal: true

require_relative "lib/stats/version"

Gem::Specification.new do |spec|
  spec.name        = "stats"
  spec.version     = Stats::VERSION
  spec.authors     = ["Relay Team"]
  spec.summary     = "Real-time stats dashboard for Nostr relay"
  spec.description = "A mountable Rails engine providing a real-time statistics dashboard"
  spec.license     = "MIT"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib,test}/**/*", "Rakefile"]
  end

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "dry-monads"
end
