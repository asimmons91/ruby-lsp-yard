# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Diagnostics
      # Linter-level behaviour: enablement, suppression, severity configuration and error isolation (FR-M5-01..04,
      # NFR-R1/R2).
      class TestLinter < Minitest::Test
        include DiagnosticsHelpers

        UNKNOWN_PARAM_SOURCE = <<~RUBY
          class LinterOwner
            # @param nope [String]
            def call(a); end
          end
        RUBY

        def test_disabled_diagnostics_return_nil
          linter = Linter.new(settings: Settings.new({"enableDiagnostics" => false}))

          assert_nil linter.run_diagnostic(TEST_URI, document_for(UNKNOWN_PARAM_SOURCE))
        end

        def test_syntax_errors_return_nil
          linter = Linter.new(settings: Settings.new({}))

          assert_nil linter.run_diagnostic(TEST_URI, document_for("def broken(\n"))
        end

        def test_deactivate_makes_the_linter_inert
          linter = Linter.new(settings: Settings.new({}))
          linter.deactivate!

          refute linter.active?
          assert_nil linter.run_diagnostic(TEST_URI, document_for(UNKNOWN_PARAM_SOURCE))
        end

        def test_unexpected_failures_return_nil
          linter = Linter.new(settings: Settings.new({}))

          Scanner.stub(:new, ->(*) { raise "boom" }) do
            assert_nil linter.run_diagnostic(TEST_URI, document_for(UNKNOWN_PARAM_SOURCE))
          end
        end

        def test_suppression_filters_diagnostics
          diagnostics = lint(<<~RUBY)
            class SuppressedOwner
              # @param nope [String]
              # yard:disable YARD/UnknownParam
              def call(a); end
            end
          RUBY

          assert_empty diagnostics
        end

        def test_suppression_is_scoped_to_the_definition
          diagnostics = lint(<<~RUBY)
            class SuppressionScopeOwner
              # @param nope [String]
              # yard:disable YARD/UnknownParam
              def suppressed(a); end

              # @param nope [String]
              def reported(a); end
            end
          RUBY

          assert_equal ["YARD/UnknownParam"], codes(diagnostics)
          assert_includes diagnostics.first.message, "reported"
        end

        def test_severity_can_be_configured
          diagnostics = lint(
            UNKNOWN_PARAM_SOURCE,
            settings: {"diagnosticRules" => {"YARD/UnknownParam" => "hint"}}
          )

          assert_equal ["YARD/UnknownParam"], codes(diagnostics)
          assert_equal Constant::DiagnosticSeverity::HINT, diagnostics.first.severity
        end

        def test_rules_can_be_turned_off
          diagnostics = lint(
            UNKNOWN_PARAM_SOURCE,
            settings: {"diagnosticRules" => {"YARD/UnknownParam" => false}}
          )

          assert_empty diagnostics
        end

        def test_a_failing_rule_does_not_take_down_the_others
          raising = Class.new(Rules::Base) do
            def self.key
              "YARD/Raising"
            end

            def self.default_severity
              :warning
            end

            def self.check(_target, _context)
              raise "boom"
            end
          end

          diagnostics = lint(UNKNOWN_PARAM_SOURCE, rules: [raising, Rules::UnknownParam])

          assert_equal ["YARD/UnknownParam"], codes(diagnostics)
        end
      end
    end
  end
end
