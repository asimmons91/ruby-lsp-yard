# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/diagnostics"

module RubyLsp
  module Yard
    module Diagnostics
      class TestSuppression < Minitest::Test
        def test_no_directive_returns_nil
          assert_nil Suppression.parse([])
          assert_nil Suppression.parse(["# @param n [Integer]", "# just prose"])
        end

        def test_named_rules_are_suppressed
          suppression = Suppression.parse([
            "# @param n [Integer]",
            "# yard:disable YARD/UnknownParam, YARD/UnresolvedType"
          ])

          refute_nil suppression
          assert suppression.suppressed?("YARD/UnknownParam")
          assert suppression.suppressed?("YARD/UnresolvedType")
          refute suppression.suppressed?("YARD/DuplicateTag")
        end

        def test_whitespace_separated_names_are_supported
          suppression = Suppression.parse(["# yard:disable YARD/UnknownParam YARD/DuplicateTag"])

          assert suppression.suppressed?("YARD/UnknownParam")
          assert suppression.suppressed?("YARD/DuplicateTag")
        end

        def test_bare_directive_suppresses_everything
          suppression = Suppression.parse(["# yard:disable"])

          assert suppression.suppressed?("YARD/Anything")
        end

        def test_the_keyword_must_start_the_comment
          assert_nil Suppression.parse(["# see yard:disable YARD/UnknownParam"])
          assert_nil Suppression.parse(["# @note yard:disable"])
        end

        def test_indented_directives_are_supported
          suppression = Suppression.parse(["  # yard:disable YARD/UnknownParam"])

          assert suppression.suppressed?("YARD/UnknownParam")
        end
      end
    end
  end
end
