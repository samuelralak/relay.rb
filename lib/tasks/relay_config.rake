# frozen_string_literal: true

namespace :relay_config do
  desc "Create a new API key"
  task :create_api_key, [ :name ] => :environment do |_, args|
    name = args[:name] || "Admin Key"
    key = ApiKey.create!(name:)
    puts "Created API key: #{key.token}"
    puts "Key prefix: #{key.key_prefix}"
    puts "\nSave this token - it will not be shown again!"
  end

  desc "List all API keys"
  task list_api_keys: :environment do
    keys = ApiKey.all

    if keys.empty?
      puts "No API keys found"
      exit 0
    end

    puts "API Keys:"
    puts "-" * 80
    keys.each do |key|
      status = key.active? ? "active" : "revoked"
      last_used = key.last_used_at&.strftime("%Y-%m-%d %H:%M") || "never"
      puts "#{key.key_prefix}... | #{key.name} | #{status} | Last used: #{last_used}"
    end
  end

  desc "Revoke an API key by prefix"
  task :revoke_api_key, [ :prefix ] => :environment do |_, args|
    prefix = args[:prefix]

    unless prefix
      puts "Usage: rake relay_config:revoke_api_key[prefix]"
      exit 1
    end

    key = ApiKey.find_by(key_prefix: prefix)

    unless key
      puts "No API key found with prefix: #{prefix}"
      exit 1
    end

    key.revoke!
    puts "Revoked API key: #{key.name} (#{key.key_prefix})"
  end
end
