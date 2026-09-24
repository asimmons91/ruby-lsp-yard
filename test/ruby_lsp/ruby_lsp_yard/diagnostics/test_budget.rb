# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/diagnostics"

module RubyLsp
  module Yard
    module Diagnostics
      class TestBudget < Minitest::Test
        def test_work_continues_before_the_deadline
          now = 0.0
          budget = Budget.new(timeout_ms: 10, clock: -> { now })

          assert budget.check!
          refute budget.exhausted?
        end

        def test_budget_is_exhausted_once_the_deadline_passes
          now = 0.0
          budget = Budget.new(timeout_ms: 10, clock: -> { now })

          Budget::CHECK_INTERVAL.times { budget.check! }
          refute budget.exhausted?

          now = 1.0
          Budget::CHECK_INTERVAL.times { budget.check! }

          assert budget.exhausted?
          refute budget.check!
          assert budget.exhausted?
        end

        def test_deadline_is_sampled_between_checks
          now = 0.0
          budget = Budget.new(timeout_ms: 10, clock: -> { now })
          now = 1.0

          # The first check does not sample the clock, so the budget is not exhausted until the interval elapses.
          assert budget.check!
          refute budget.exhausted?
        end
      end
    end
  end
end
