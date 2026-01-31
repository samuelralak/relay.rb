# frozen_string_literal: true

module Stats
  class CollectEvents < ::BaseService
    # Cache TTLs for expensive queries
    TOTAL_COUNT_CACHE_TTL = 1.minute
    PER_MINUTE_CACHE_TTL = 30.seconds
    BY_KIND_CACHE_TTL = 5.minutes
    LAST_7_DAYS_CACHE_TTL = 5.minutes

    def call
      event_class = Stats.event_class

      Success(
        total: cached_total_count(event_class),
        today: count_received_today(event_class),
        per_minute: calculate_per_minute(event_class),
        by_kind: count_by_kind(event_class),
        last_7_days: count_last_7_days(event_class)
      )
    rescue StandardError => e
      Rails.logger.error "[Stats] CollectEvents failed: #{e.class} - #{e.message}"
      Failure(error: e.message)
    end

    private

    def cached_total_count(klass)
      Rails.cache.fetch("stats:events:total", expires_in: TOTAL_COUNT_CACHE_TTL) do
        # paranoia gem adds default scope excluding deleted records
        klass.count
      end
    end

    def count_received_today(klass)
      # Use first_seen_at: when the relay received the event (not nostr_created_at which is protocol timestamp)
      klass.where("first_seen_at >= ?", Date.current.beginning_of_day).count
    end

    def calculate_per_minute(klass)
      Rails.cache.fetch("stats:events:per_minute", expires_in: PER_MINUTE_CACHE_TTL) do
        # Use first_seen_at for processing rate (when relay received it)
        window_minutes = 5
        recent = klass.where("first_seen_at > ?", window_minutes.minutes.ago).count
        (recent.to_f / window_minutes).round(2)
      end
    end

    def count_by_kind(klass)
      Rails.cache.fetch("stats:events:by_kind", expires_in: BY_KIND_CACHE_TTL) do
        # paranoia default scope handles deleted_at filtering
        klass.group(:kind)
             .count
             .sort_by { |k, _| k }
             .to_h
      end
    end

    def count_last_7_days(klass)
      # Use first_seen_at: when relay received the events (not protocol timestamp)
      # Cache key includes date to auto-invalidate at midnight
      cache_key = "stats:events:last_7_days:#{Date.current}"

      Rails.cache.fetch(cache_key, expires_in: LAST_7_DAYS_CACHE_TTL) do
        klass.where("first_seen_at > ?", 7.days.ago)
             .group("DATE(first_seen_at)")
             .count
             .sort
             .to_h
             .transform_keys(&:to_s)
      end
    end
  end
end
