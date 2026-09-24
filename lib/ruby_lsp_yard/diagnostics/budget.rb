# frozen_string_literal: true

module RubyLsp
  module Yard
    module Diagnostics
      # The diagnostics budget (FR-M5-04). Cheap rules always run; once the deadline passes, {#check!} stays false
      # and the linter skips the expensive rules instead of blocking the request. The deadline is only sampled every
      # {CHECK_INTERVAL} checks so reading the monotonic clock stays off the hot path.
      class Budget
        DEFAULT_TIMEOUT_MS = 100
        CHECK_INTERVAL = 16

        attr_reader :checks

        def initialize(timeout_ms: DEFAULT_TIMEOUT_MS, clock: nil)
          @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
          @deadline = @clock.call + (timeout_ms / 1000.0)
          @checks = 0
          @exhausted = false
        end

        # Returns true while work may continue. Once the deadline has passed the budget stays exhausted, so later
        # rules are skipped even if the clock is sampled again.
        def check!
          return false if @exhausted

          @checks += 1
          return true unless (@checks % CHECK_INTERVAL).zero?

          @exhausted = true if @clock.call > @deadline
          !@exhausted
        end

        def exhausted?
          @exhausted
        end
      end
    end
  end
end
