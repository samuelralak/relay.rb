# frozen_string_literal: true

namespace :db do
  desc "Verify all database connections are properly configured"
  task check_connections: :environment do
    puts "=" * 60
    puts "Database Connection Verification"
    puts "=" * 60
    puts

    # Get all configured databases
    configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)

    configs.each do |config|
      db_name = config.name
      spec_name = config.spec_name || config.name

      print "#{db_name.ljust(20)}"

      begin
        # Establish connection to this database
        ActiveRecord::Base.establish_connection(config)
        connection = ActiveRecord::Base.connection

        # Test the connection
        result = connection.execute("SELECT 1 AS connected")
        replica_status = config.replica? ? " (replica)" : ""

        puts "OK#{replica_status}"
        puts "  URL: #{config.url&.gsub(/:[^:@]+@/, ':***@') || 'N/A'}"
        puts "  Adapter: #{config.adapter}"
        puts "  Pool: #{config.pool}"
        puts
      rescue StandardError => e
        puts "FAILED"
        puts "  Error: #{e.message}"
        puts
      end
    end

    # Reconnect to primary
    ActiveRecord::Base.establish_connection(:primary)

    puts "=" * 60
    puts "Connection Pool Stats (Primary)"
    puts "=" * 60
    pool = ActiveRecord::Base.connection_pool
    puts "  Size: #{pool.size}"
    puts "  Connections: #{pool.connections.size}"
    puts "  Active: #{pool.connections.count(&:in_use?)}"
    puts
  end

  desc "Run migrations for all databases"
  task migrate_all: :environment do
    puts "Migrating primary database..."
    Rake::Task["db:migrate"].invoke

    %w[cache queue cable].each do |db|
      puts "\nMigrating #{db} database..."
      Rake::Task["db:migrate:#{db}"].invoke
    end

    puts "\nAll migrations complete!"
  end

  desc "Check migration status for all databases"
  task status_all: :environment do
    puts "=" * 60
    puts "Primary Database"
    puts "=" * 60
    Rake::Task["db:migrate:status"].invoke

    %w[cache queue cable].each do |db|
      puts "\n#{'=' * 60}"
      puts "#{db.capitalize} Database"
      puts "=" * 60
      begin
        Rake::Task["db:migrate:status:#{db}"].invoke
      rescue StandardError => e
        puts "  Error: #{e.message}"
      end
    end
  end
end
