# frozen_string_literal: true

module RelaySync
  # Publishes events to remote relays with rate limiting and error handling
  class EventPublisher
    attr_reader :connection

    def initialize(connection)
      @connection = connection
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @results = {}
    end

    # Publish a single event and wait for OK response
    # @param event [Hash, #raw_event] event to publish (Hash or object responding to raw_event)
    # @param timeout [Integer] timeout in seconds
    # @return [Hash] result with :success, :message
    def publish(event, timeout: 10)
      event_data = event.respond_to?(:raw_event) ? event.raw_event : event
      event_id = event_data["id"] || event_data[:id]

      # Register OK handler with Manager
      RelaySync.manager.register_ok_handler(event_id) do |success, message|
        @mutex.synchronize do
          @results[event_id] = { success:, message: }
          @condition.broadcast
        end
      end

      # Send the event
      connection.publish_event(event_data)

      # Wait for OK response
      wait_for_ok(event_id, timeout)
    ensure
      # Clean up handler if still registered
      RelaySync.manager.unregister_ok_handler(event_id)
    end

    # Publish multiple events in batches
    # @param events [Array<Hash, #raw_event>] events to publish
    # @param batch_size [Integer] events per batch
    # @param delay [Float] delay between batches in seconds
    # @yield [event, result] called for each published event
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

      { published:, failed:, duplicates: }
    end

    private

    def wait_for_ok(event_id, timeout)
      deadline = Time.now + timeout

      @mutex.synchronize do
        loop do
          return @results.delete(event_id) if @results.key?(event_id)

          remaining = deadline - Time.now
          return { success: false, message: "timeout" } if remaining <= 0

          # Wait with timeout using ConditionVariable
          @condition.wait(@mutex, remaining)
        end
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
