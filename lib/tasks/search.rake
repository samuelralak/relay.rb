# frozen_string_literal: true

namespace :search do
  desc "Create OpenSearch index"
  task create_index: :environment do
    client = RelaySearch::Client.client
    index = RelaySearch::IndexConfig::INDEX_NAME

    if client.indices.exists?(index:)
      puts "Index '#{index}' already exists"
    else
      client.indices.create(
        index:,
        body: {
          mappings: RelaySearch::IndexConfig::MAPPINGS,
          settings: RelaySearch::IndexConfig::SETTINGS
        }
      )
      puts "Created index '#{index}'"
    end
  end

  desc "Delete OpenSearch index"
  task delete_index: :environment do
    client = RelaySearch::Client.client
    index = RelaySearch::IndexConfig::INDEX_NAME

    if client.indices.exists?(index:)
      client.indices.delete(index:)
      puts "Deleted index '#{index}'"
    else
      puts "Index '#{index}' does not exist"
    end
  end

  desc "Reindex all events to OpenSearch"
  task reindex: :environment do
    result = Search::BulkIndexEvents.call
    if result.success?
      values = result.value!
      puts "Reindexed #{values[:indexed]} events"
      puts "Errors: #{values[:errors]}" if values[:errors] > 0
    else
      puts "Reindex failed: #{result.failure}"
    end
  end

  desc "Show OpenSearch status"
  task status: :environment do
    puts "OpenSearch Status"
    puts "=" * 40
    puts "Enabled: #{RelaySearch::Client.enabled?}"
    puts "Available: #{RelaySearch::Client.available?}"

    if RelaySearch::Client.available?
      index = RelaySearch::IndexConfig::INDEX_NAME
      client = RelaySearch::Client.client

      if client.indices.exists?(index:)
        count = client.count(index:)["count"]
        puts "Index: #{index}"
        puts "Documents: #{count}"
      else
        puts "Index: #{index} (not created)"
      end
    end
  end
end
