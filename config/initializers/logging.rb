# frozen_string_literal: true

# Centralized logging configuration
# All components use AppLogger for consistent structured logging
#
# Usage:
#   - Services/Jobs: include Loggable (or JobLoggable), then use `logger.info "message", key: value`
#   - Lib files: use `self.class.tagged_logger.info "message", key: value`
#   - Direct: AppLogger[:ComponentName].info "message", key: value

Rails.application.config.after_initialize do
  AppLogger[:Rails].info "Logging initialized",
    level: ENV.fetch("LOG_LEVEL", "info"),
    format: ENV.fetch("LOG_FORMAT", "string")
end
