# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    class TestSettings < Minitest::Test
      def test_defaults_work_with_no_configuration
        settings = Settings.new(nil)

        assert settings.enabled?(:completion)
        assert settings.enabled?(:hover)
        assert settings.enabled?(:signature_help)
        assert settings.enabled?(:definition)
        assert settings.enabled?(:diagnostics)
        assert settings.enabled?(:authoring)
        assert settings.enabled?(:snippets)
        assert settings.enabled?(:macros)
        assert settings.enabled?(:domains)
        assert settings.enabled?(:solargraph)
        assert settings.enabled?(:inline_types)
        refute settings.enabled?(:inlay_hints)
        refute settings.debug_inference?
        assert_equal :info, settings.log_level
      end

      def test_m7_features_can_be_disabled
        settings = Settings.new({enableMacros: false, enableDomains: false, enableSolargraph: false, enableInlineTypes: false})

        refute settings.enabled?(:macros)
        refute settings.enabled?(:domains)
        refute settings.enabled?(:solargraph)
        refute settings.enabled?(:inline_types)
      end

      def test_reads_symbol_and_string_keys
        settings = Settings.new({:enableHover => false, "enableCompletion" => false, "logLevel" => "debug"})

        refute settings.enabled?(:hover)
        refute settings.enabled?(:completion)
        assert settings.enabled?(:definition)
        assert_equal :debug, settings.log_level
      end

      def test_debug_inference_can_be_enabled
        assert Settings.new({debugInference: true}).debug_inference?
      end

      def test_unknown_features_are_disabled
        refute Settings.new(nil).enabled?(:bogus)
      end

      def test_malformed_input_falls_back_to_defaults
        assert Settings.new("nope").enabled?(:completion)

        settings = Settings.new({enableHover: "bogus", logLevel: 42})

        assert settings.enabled?(:hover)
        assert_equal :info, settings.log_level
      end

      def test_boolean_strings_are_coerced
        refute Settings.new({"enableHover" => "false"}).enabled?(:hover)
        assert Settings.new({enableHover: "true"}).enabled?(:hover)
      end

      def test_rule_severities_default_to_nil
        assert_nil Settings.new(nil).rule_severity("YARD/UnknownParam")
      end

      def test_rule_severities_are_read_from_diagnostic_rules
        settings = Settings.new({
          diagnosticRules: {
            "YARD/MissingParam" => "warning",
            :"YARD/MissingReturn" => "error"
          }
        })

        assert_equal :warning, settings.rule_severity("YARD/MissingParam")
        assert_equal :error, settings.rule_severity("YARD/MissingReturn")
        assert_nil settings.rule_severity("YARD/UnknownParam")
      end

      def test_rules_can_be_disabled
        settings = Settings.new({
          "diagnosticRules" => {
            "YARD/UnknownParam" => false,
            "YARD/MissingParam" => "off",
            "YARD/MissingReturn" => "NONE"
          }
        })

        assert_equal :off, settings.rule_severity("YARD/UnknownParam")
        assert_equal :off, settings.rule_severity("YARD/MissingParam")
        assert_equal :off, settings.rule_severity("YARD/MissingReturn")
      end

      def test_invalid_rule_values_fall_back_to_defaults
        assert_nil Settings.new({diagnosticRules: "bogus"}).rule_severity("YARD/UnknownParam")
        assert_nil Settings.new({diagnosticRules: {"YARD/UnknownParam" => "loud"}})
          .rule_severity("YARD/UnknownParam")
        assert_equal :hint, Settings.new({diagnosticRules: {"YARD/UnknownParam" => "Hint"}})
          .rule_severity("YARD/UnknownParam")
      end
    end
  end
end
