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
        refute settings.enabled?(:inlay_hints)
        refute settings.debug_inference?
        assert_equal :info, settings.log_level
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
    end
  end
end
