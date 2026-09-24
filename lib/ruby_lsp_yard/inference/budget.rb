# frozen_string_literal: true

module RubyLsp
  module Yard
    module Inference
      # The inference budget (NFR-P3, FR-M2-12). Inference stops after a fixed deadline, a depth of 8 chained calls
      # or a repeated (method, receiver type) pair, and returns Unknown instead of blocking the request. The deadline
      # is only sampled every {CHECK_INTERVAL} checks so that reading the monotonic clock stays off the hot path.
      class Budget
        class Exceeded < StandardError; end

        DEFAULT_TIMEOUT_MS = 20
        DEFAULT_MAX_DEPTH = 8
        CHECK_INTERVAL = 32

        attr_reader :visited

        def initialize(
          timeout_ms: DEFAULT_TIMEOUT_MS,
          max_depth: DEFAULT_MAX_DEPTH,
          check_interval: CHECK_INTERVAL,
          clock: nil
        )
          @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          @deadline = @clock.call + (timeout_ms / 1000.0)
          @max_depth = max_depth
          @check_interval = check_interval
          @checks = 0
          @visited = {}
        end

        # Raises {Exceeded} when `depth` is past the limit or the deadline has passed.
        def check!(depth)
          raise Exceeded if depth > @max_depth

          @checks += 1
          return unless (@checks % @check_interval).zero?
          return if @clock.call <= @deadline

          raise Exceeded
        end

        # Marks `key` as visited. Returns false when it was already seen, so callers can cut recursion off.
        def visit(key)
          return false if @visited.key?(key)

          @visited[key] = true
          true
        end
      end
    end
  end
end
