# frozen_string_literal: true

# Provides consistent logging for jobs
# Functionally identical to Loggable but kept separate for clarity
module JobLoggable
  extend ActiveSupport::Concern
  include Loggable
end
