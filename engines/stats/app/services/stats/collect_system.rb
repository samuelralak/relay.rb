# frozen_string_literal: true

module Stats
  class CollectSystem < ::BaseService
    # Cache TTL for expensive system metrics (reduces shell/file operations)
    MEMORY_RSS_CACHE_TTL = 10.seconds
    CPU_CACHE_TTL = 5.seconds

    def call
      Success(
        memory: collect_memory,
        cpu: collect_cpu,
        process: collect_process,
        database: collect_database
      )
    rescue StandardError => e
      Rails.logger.error "[Stats] CollectSystem failed: #{e.class} - #{e.message}"
      Failure(error: e.message)
    end

    private

    def collect_memory
      {
        rss_mb: cached_memory_rss_mb,
        # GC stats are cheap and should be real-time
        heap_allocated_pages: GC.stat[:heap_allocated_pages],
        total_allocated_objects: GC.stat[:total_allocated_objects]
      }
    end

    def cached_memory_rss_mb
      Rails.cache.fetch("stats:system:memory_rss", expires_in: MEMORY_RSS_CACHE_TTL) do
        memory_rss_mb
      end
    end

    def memory_rss_mb
      # Linux: read from /proc
      if File.exist?("/proc/#{Process.pid}/status")
        match = File.read("/proc/#{Process.pid}/status").match(/VmRSS:\s+(\d+)/)
        return (match[1].to_i / 1024.0).round(2) if match
      end

      # macOS/fallback: use ps command
      (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(2)
    end

    def collect_cpu
      Rails.cache.fetch("stats:system:cpu", expires_in: CPU_CACHE_TTL) do
        {
          load_percent: calculate_cpu_percent,
          load_average: system_load_average
        }
      end
    end

    def calculate_cpu_percent
      # Calculate CPU usage by comparing process times over a short interval
      # This gives instantaneous CPU usage rather than cumulative time
      times1 = Process.times
      clock1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      sleep(0.1) # Brief sample interval

      times2 = Process.times
      clock2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      cpu_time = (times2.utime - times1.utime) + (times2.stime - times1.stime)
      wall_time = clock2 - clock1

      return 0.0 if wall_time <= 0

      ((cpu_time / wall_time) * 100).round(1)
    end

    def system_load_average
      # Get system load average (1-minute)
      if File.exist?("/proc/loadavg")
        File.read("/proc/loadavg").split.first.to_f.round(2)
      else
        # macOS: use sysctl
        result = `sysctl -n vm.loadavg 2>/dev/null`.strip
        match = result.match(/\{\s*([\d.]+)/)
        match ? match[1].to_f.round(2) : 0.0
      end
    rescue StandardError
      0.0
    end

    def collect_process
      {
        pid: Process.pid,
        thread_count: Thread.list.size,
        uptime_seconds: calculate_uptime,
        ruby_version: RUBY_VERSION,
        rails_version: Rails.version
      }
    end

    def calculate_uptime
      # Try multiple methods to get process uptime
      uptime_from_rails_boot ||
        uptime_from_proc ||
        uptime_from_ps ||
        0
    end

    def uptime_from_rails_boot
      return nil unless Rails.application.respond_to?(:initialized_at)
      return nil unless Rails.application.initialized_at

      (Time.current - Rails.application.initialized_at).to_i
    end

    def uptime_from_proc
      return nil unless File.exist?("/proc/#{Process.pid}/stat")

      stat = File.read("/proc/#{Process.pid}/stat").split
      start_time_ticks = stat[21].to_i
      clock_ticks_per_sec = `getconf CLK_TCK`.to_i
      clock_ticks_per_sec = 100 if clock_ticks_per_sec <= 0

      boot_time = File.read("/proc/uptime").split.first.to_f
      process_start = start_time_ticks.to_f / clock_ticks_per_sec

      (boot_time - process_start).to_i
    rescue StandardError
      nil
    end

    def uptime_from_ps
      # macOS and other Unix: use ps to get elapsed time
      result = `ps -o etime= -p #{Process.pid} 2>/dev/null`.strip
      return nil if result.empty?

      parse_elapsed_time(result)
    rescue StandardError
      nil
    end

    def parse_elapsed_time(etime)
      # Parse ps etime format: [[dd-]hh:]mm:ss
      parts = etime.split(/[-:]/)
      case parts.length
      when 2 # mm:ss
        parts[0].to_i * 60 + parts[1].to_i
      when 3 # hh:mm:ss
        parts[0].to_i * 3600 + parts[1].to_i * 60 + parts[2].to_i
      when 4 # dd-hh:mm:ss
        parts[0].to_i * 86400 + parts[1].to_i * 3600 + parts[2].to_i * 60 + parts[3].to_i
      else
        0
      end
    end

    def collect_database
      pool = ActiveRecord::Base.connection_pool
      {
        pool_size: pool.size,
        connections_in_use: pool.connections.count(&:in_use?),
        waiting_in_queue: pool.num_waiting_in_queue
      }
    end
  end
end
