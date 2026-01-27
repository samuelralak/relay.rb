# frozen_string_literal: true

require "singleton"
require "eventmachine"

module RelaySync
  # Shared EventMachine reactor for all connections
  class Reactor
    include Singleton

    def initialize
      @mutex = Mutex.new
      @running = false
      @thread = nil
    end

    def start
      @mutex.synchronize do
        return if @running

        @running = true

        # If EM is already running (e.g. started by Puma), we don't need to start a new thread
        unless EM.reactor_running?
          @thread = Thread.new do
            EM.run do
              # Reactor is now running
            end
          end

          # Wait for reactor to start
          sleep 0.1 until EM.reactor_running?
        end
      end
    end

    def stop
      @mutex.synchronize do
        return unless @running

        # Only stop EM if we started it (we have a thread)
        if @thread
          EM.stop_event_loop if EM.reactor_running?
          @thread.join(5)
          @thread = nil
        end

        @running = false
      end
    end

    def running?
      @running && EM.reactor_running?
    end

    def schedule(&)
      start unless running?
      EM.next_tick(&)
    end
  end
end
