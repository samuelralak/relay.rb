# frozen_string_literal: true

module RelaySync
  # Publishes events to remote relays with rate limiting and error handling
  class EventPublisher
    attr_reader :connection, :pending_oks, :results

    def initialize(connection)
      @connection = connection
      @pending_oks = {}
      @results = {}
      @mutex = Mutex.new
    end

    # Publish a single event and wait for OK response
    # @param event [Event, Hash] event to publish
    # @param timeout [Integer] timeout in seconds
    # @return [Hash] result with :success, :message
    def publish(event, timeout: 10)
      event_data = event.is_a?(Event) ? event.raw_event : event
      event_id = event_data["id"] || event_data[:id]

      # Register pending OK
      @mutex.synchronize do
        @pending_oks[event_id] = { event: event_data, time: Time.current }
      end

      # Send the event
      connection.publish_event(event_data)

      # Wait for OK response
      wait_for_ok(event_id, timeout)
    end

    # Publish multiple events in batches
    # @param events [Array<Event, Hash>] events to publish
    # @param batch_size [Integer] events per batch
    # @param delay [Float] delay between batches in seconds
    # @yield [result] called for each published event
    # @return [Hash] summary of results
    def publish_batch(events, batch_size: 50, delay: 0.1)
      published = 0
      failed = 0
      duplicates = 0

      events.each_slice(batch_size) do |batch|
        batch.each do |event|
          result = publish(event)

          case classify_result(result)
          when :success
            published += 1
          when :duplicate
            duplicates += 1
          when :rate_limited
            # Back off and retry
            sleep delay * 5
            retry_result = publish(event)
            if classify_result(retry_result) == :success
              published += 1
            else
              failed += 1
            end
          else
            failed += 1
          end

          yield(event, result) if block_given?
        end

        sleep delay
      end

      { published: published, failed: failed, duplicates: duplicates }
    end

    # Handle incoming OK response
    # @param event_id [String] event ID
    # @param success [Boolean] whether relay accepted the event
    # @param message [String] optional message from relay
    def handle_ok(event_id, success, message)
      @mutex.synchronize do
        if @pending_oks.key?(event_id)
          @results[event_id] = { success: success, message: message, time: Time.current }
          @pending_oks.delete(event_id)
        end
      end
    end

    private

    def wait_for_ok(event_id, timeout)
      deadline = Time.current + timeout

      loop do
        @mutex.synchronize do
          return @results.delete(event_id) if @results.key?(event_id)
        end

        return { success: false, message: "timeout" } if Time.current > deadline

        sleep 0.05
      end
    end

    def classify_result(result)
      return :success if result[:success]

      message = result[:message].to_s.downcase

      if message.include?("duplicate")
        :duplicate
      elsif message.include?("rate") || message.include?("limit")
        :rate_limited
      elsif message.include?("blocked") || message.include?("rejected")
        :blocked
      else
        :failed
      end
    end
  end
end
