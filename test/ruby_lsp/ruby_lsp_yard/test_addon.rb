# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    class TestAddon < Minitest::Test
      def test_that_it_has_a_version_number
        refute_nil ::RubyLsp::Yard::VERSION
      end

      def test_addon_is_discoverable
        assert_operator ::RubyLsp::Yard::Addon, :<, ::RubyLsp::Addon
      end

      def test_addon_metadata
        addon = ::RubyLsp::Yard::Addon.new

        assert_equal "Ruby LSP YARD", addon.name
        assert_equal ::RubyLsp::Yard::VERSION, addon.version
      end
    end
  end
end
