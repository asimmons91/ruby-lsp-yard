# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    class TestAddon < Minitest::Test
      include RubyLsp::TestHelper

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

      def test_activation_builds_the_indexer_adapter
        addon = activate_addon

        refute addon.error?
        assert_instance_of Indexer::RubyIndexerAdapter, addon.indexer
        assert_instance_of SignatureStore, addon.signature_store
        assert_instance_of Inference::ReceiverInferrer, addon.receiver_inferrer
        refute_nil addon.log
      end

      def test_activation_reads_addon_settings
        addon = activate_addon(enableHover: false, logLevel: "debug")

        refute addon.settings.enabled?(:hover)
        assert addon.settings.enabled?(:completion)
        assert_equal :debug, addon.settings.log_level
      end

      def test_deactivate_releases_references
        addon = activate_addon
        addon.deactivate

        assert_nil addon.indexer
        assert_nil addon.signature_store
        assert_nil addon.receiver_inferrer
        assert_nil addon.settings
        assert_nil addon.log
      end

      def test_watched_file_changes_are_forwarded_to_the_adapter
        addon = activate_addon
        received = []
        addon.indexer.subscribe { |uris| received.concat(uris) }

        addon.workspace_did_change_watched_files([{uri: "file:///tmp/foo.rb", type: 2}])

        assert_equal ["file:///tmp/foo.rb"], received.map(&:to_s)
      end

      def test_watched_file_changes_ignore_invalid_uris
        addon = activate_addon
        received = []
        addon.indexer.subscribe { |uris| received.concat(uris) }

        addon.workspace_did_change_watched_files([{uri: "not a uri"}, {"uri" => "file:///tmp/bar.rb"}])

        assert_equal ["file:///tmp/bar.rb"], received.map(&:to_s)
      end

      def test_addon_is_discovered_and_activated_by_the_server
        with_server("# frozen_string_literal: true\n") do |_server, _uri|
          addon = RubyLsp::Addon.addons.find { |candidate| candidate.name == "Ruby LSP YARD" }

          refute_nil addon
          refute addon.error?
          assert_instance_of Indexer::RubyIndexerAdapter, addon.indexer
        end
      end

      def test_addon_settings_are_read_from_addon_settings_key
        with_server do |server, _uri|
          server.global_state.apply_options({
            initializationOptions: {addonSettings: {"Ruby LSP YARD" => {enableHover: false}}}
          })

          assert_equal({enableHover: false}, server.global_state.settings_for_addon("Ruby LSP YARD"))
        end
      end

      private

      def activate_addon(settings = {})
        global_state = RubyLsp::GlobalState.new

        global_state.stub(:settings_for_addon, settings) do
          addon = ::RubyLsp::Yard::Addon.new
          addon.activate(global_state, Thread::Queue.new)
          addon
        end
      end
    end
  end
end
