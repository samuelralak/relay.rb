# frozen_string_literal: true

module Events
  module Classifiable
    extend ActiveSupport::Concern

    included do
      scope :metadata_events, -> { where(kind: Kinds::METADATA) }
      scope :text_notes, -> { where(kind: Kinds::TEXT_NOTE) }
      scope :contacts_events, -> { where(kind: Kinds::CONTACTS) }
      scope :reactions, -> { where(kind: Kinds::REACTION) }
      scope :deletions, -> { where(kind: Kinds::DELETION) }

      # Additional kind-based scopes
      scope :reposts, -> { where(kind: Kinds::REPOST) }
      scope :long_form, -> { where(kind: Kinds::LONG_FORM) }
      scope :zaps, -> { where(kind: Kinds::ZAP) }
    end

    # Delegate classification checks to Kinds module
    def regular?
      Kinds.regular?(kind)
    end

    def replaceable?
      Kinds.replaceable?(kind)
    end

    def ephemeral?
      Kinds.ephemeral?(kind)
    end

    def addressable?
      Kinds.addressable?(kind)
    end
    alias parameterized_replaceable? addressable?

    def storable?
      Kinds.storable?(kind)
    end

    def classification
      Kinds.classification(kind)
    end
  end
end
