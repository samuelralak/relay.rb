# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Enable read/write splitting when replica is configured
  # Writes go to :primary, reads go to :primary_replica (if available)
  if ENV["DATABASE_REPLICA_URL"].present?
    connects_to database: { writing: :primary, reading: :primary_replica }
  end
end
