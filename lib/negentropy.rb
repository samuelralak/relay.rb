# frozen_string_literal: true

require_relative "negentropy/version"
require_relative "negentropy/errors"
require_relative "negentropy/types"
require_relative "negentropy/varint"
require_relative "negentropy/fingerprint"
require_relative "negentropy/bound"
require_relative "negentropy/message"
require_relative "negentropy/storage"
require_relative "negentropy/reconciler"
require_relative "negentropy/reconciler/client"
require_relative "negentropy/reconciler/server"

module Negentropy
  PROTOCOL_VERSION = 0x61
end
