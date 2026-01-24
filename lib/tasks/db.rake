# frozen_string_literal: true

# Enhance database tasks to include Solid Queue schema

namespace :db do
  desc "Load Solid Queue schema"
  task load_queue_schema: :environment do
    queue_schema = Rails.root.join("db/queue_schema.rb")
    if queue_schema.exist?
      puts "Loading Solid Queue schema..."
      load queue_schema
    end
  end
end

# Auto-load queue schema after db:reset and db:setup
%w[db:reset db:setup].each do |task|
  Rake::Task[task].enhance do
    Rake::Task["db:load_queue_schema"].invoke
  end
end
