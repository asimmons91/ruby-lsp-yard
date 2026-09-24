# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/inference"

module RubyLsp
  module Yard
    module Inference
      class TestBudget < Minitest::Test
        def test_depth_limit_raises
          budget = Budget.new(max_depth: 2)

          budget.check!(2)
          assert_raises(Budget::Exceeded) { budget.check!(3) }
        end

        def test_visit_cuts_off_repeats
          budget = Budget.new

          assert budget.visit([:owner, :name])
          refute budget.visit([:owner, :name])
        end

        def test_deadline_raises
          now = 0.0
          clock = -> { now }
          budget = Budget.new(timeout_ms: 10, check_interval: 1, clock: clock)

          budget.check!(0)
          now = 1.0

          assert_raises(Budget::Exceeded) { budget.check!(0) }
        end
      end
    end
  end
end
