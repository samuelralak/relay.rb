# frozen_string_literal: true

# Provides soft delete functionality via acts_as_paranoid.
# Include in models that should use deleted_at instead of hard deletes.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    acts_as_paranoid
  end
end
