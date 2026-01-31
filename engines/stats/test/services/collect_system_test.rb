# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../app/services/stats/collect_system"

module Stats
  class CollectSystemTest < Minitest::Test
    def test_returns_success_result
      result = CollectSystem.call

      assert result.success?, "Expected success, got: #{result.failure}"
    end

    def test_includes_memory_stats
      result = CollectSystem.call

      memory = result.value![:memory]
      assert memory.key?(:rss_mb)
      assert memory.key?(:heap_allocated_pages)
      assert memory.key?(:total_allocated_objects)
    end

    def test_memory_rss_is_numeric
      result = CollectSystem.call

      assert_kind_of Numeric, result.value![:memory][:rss_mb]
    end

    def test_includes_cpu_stats
      result = CollectSystem.call

      cpu = result.value![:cpu]
      assert cpu.key?(:load_percent), "Missing :load_percent key"
      assert cpu.key?(:load_average), "Missing :load_average key"
    end

    def test_cpu_load_percent_is_valid
      result = CollectSystem.call

      cpu = result.value![:cpu]
      # CPU load percent should be between 0 and 100 (or slightly higher for multi-core)
      assert_kind_of Numeric, cpu[:load_percent]
      assert cpu[:load_percent] >= 0, "CPU load percent should be non-negative"
    end

    def test_cpu_load_average_is_valid
      result = CollectSystem.call

      cpu = result.value![:cpu]
      assert_kind_of Numeric, cpu[:load_average]
      assert cpu[:load_average] >= 0, "Load average should be non-negative"
    end

    def test_includes_process_info
      result = CollectSystem.call

      process_info = result.value![:process]
      assert_equal Process.pid, process_info[:pid]
      assert process_info[:thread_count] >= 1
      assert_equal RUBY_VERSION, process_info[:ruby_version]
      assert_equal "8.1.1", process_info[:rails_version]
    end

    def test_includes_database_stats
      result = CollectSystem.call

      database = result.value![:database]
      assert_equal 10, database[:pool_size]
      assert_equal 1, database[:connections_in_use]
      assert_equal 0, database[:waiting_in_queue]
    end

    def test_uptime_is_positive_or_zero
      result = CollectSystem.call

      uptime = result.value![:process][:uptime_seconds]
      assert uptime >= 0, "Uptime should be non-negative"
    end
  end
end
