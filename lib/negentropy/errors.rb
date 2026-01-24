# frozen_string_literal: true

module Negentropy
  class Error < StandardError; end
  class ProtocolError < Error; end
  class StorageError < Error; end
  class MessageError < Error; end
end
