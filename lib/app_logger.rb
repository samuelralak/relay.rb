# frozen_string_literal: true

require "dry/logger"

module AppLogger
  class << self
    # Get a cached tagged logger for a component
    # @param tag [String, Symbol] component identifier
    # @return [TaggedLogger]
    def [](tag)
      tagged_loggers[tag.to_s] ||= TaggedLogger.new(logger:, tag: tag.to_s)
    end

    def logger
      @logger ||= build_logger
    end

    def reset!
      @logger = nil
      @tagged_loggers = nil
    end

    private

    def tagged_loggers
      @tagged_loggers ||= {}
    end

    def build_logger
      Dry.Logger(:app, level: log_level, template: "%<message>s %<payload>s") do |setup|
        setup.add_backend(formatter: formatter_type)
      end
    end

    def log_level
      ENV.fetch("LOG_LEVEL", "info").to_sym
    end

    def formatter_type
      ENV["LOG_FORMAT"] == "json" ? :json : :string
    end
  end

  # Tagged logger using dry-initializer
  class TaggedLogger
    extend Dry::Initializer

    option :logger
    option :tag, proc(&:to_s)

    def debug(message, **payload)
      logger.debug(format_message(message), **payload)
    end

    def info(message, **payload)
      logger.info(format_message(message), **payload)
    end

    def warn(message, **payload)
      logger.warn(format_message(message), **payload)
    end

    def error(message, **payload)
      logger.error(format_message(message), **payload)
    end

    def exception(error, message = nil, **payload)
      logger.error(format_message(message || error.class.name), exception: error, **payload)
    end

    private

    def format_message(message)
      "[#{tag}] #{message}"
    end
  end
end
