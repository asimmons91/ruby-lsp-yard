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
        assert_instance_of Indexer.adapter_class, addon.indexer
        assert_instance_of SignatureStore, addon.signature_store
        assert_instance_of Inference::Engine, addon.inference
        refute_nil addon.log
        assert_instance_of Rbs::Loader, addon.rbs_loader
        assert_instance_of Rbs::Source, addon.rbs_source
        assert_instance_of Gems::Cache, addon.gem_cache
        assert_instance_of Diagnostics::Linter, addon.diagnostics
      ensure
        addon&.deactivate
      end

      def test_the_linter_is_registered_under_the_yard_identifier
        addon, global_state = activate_with_linters

        assert_includes global_state.active_linters, addon.diagnostics
      ensure
        addon&.deactivate
      end

      def test_linter_registration_respects_enable_diagnostics
        addon, global_state = activate_with_linters({enableDiagnostics: false})

        assert_empty global_state.active_linters
      ensure
        addon&.deactivate
      end

      def test_core_types_can_be_disabled
        addon = activate_addon(enableCoreTypes: false)

        assert_nil addon.rbs_loader
        assert_nil addon.rbs_source
      ensure
        addon&.deactivate
      end

      def test_activation_registers_the_authoring_patch
        addon = activate_addon

        assert_equal addon, Authoring::Registry.current
        assert Authoring::Patch.installed?
        assert addon.snippets?
      ensure
        addon&.deactivate
        assert_nil Authoring::Registry.current
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
        assert_nil addon.inference
        assert_nil addon.settings
        assert_nil addon.log
        assert_nil addon.rbs_loader
        assert_nil addon.rbs_source
        assert_nil addon.gem_cache
        assert_nil addon.diagnostics
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
          assert_instance_of Indexer.adapter_class, addon.indexer
        end
      end

      def test_addon_settings_are_read_from_the_settings_key
        addon = activate_addon_with_raw_settings({
          ::RubyLsp::Yard::Addon::SETTINGS_KEY => {enableHover: false}
        })

        refute addon.settings.enabled?(:hover)
        assert addon.settings.enabled?(:completion)
      end

      def test_addon_settings_ignore_the_display_name_key
        addon = activate_addon_with_raw_settings({"Ruby LSP YARD" => {enableHover: false}})

        assert addon.settings.enabled?(:hover)
      end

      private

      def teardown
        @addon&.deactivate
      end

      def activate_addon(settings = {})
        global_state = RubyLsp::GlobalState.new

        global_state.stub(:settings_for_addon, settings) do
          @addon = ::RubyLsp::Yard::Addon.new
          @addon.activate(global_state, Thread::Queue.new)
        end
        @addon
      end

      # Activates the add-on with a real `GlobalState` whose `addonSettings` are `settings` verbatim, so the settings
      # key lookup is exercised end to end.
      def activate_addon_with_raw_settings(settings)
        global_state = RubyLsp::GlobalState.new
        global_state.apply_options({initializationOptions: {addonSettings: settings}})

        @addon = ::RubyLsp::Yard::Addon.new
        @addon.activate(global_state, Thread::Queue.new)
        @addon
      end

      # Activates the add-on with the `yard` linter configured, so `active_linters` can resolve it.
      def activate_with_linters(settings = {})
        global_state = RubyLsp::GlobalState.new
        global_state.apply_options({initializationOptions: {linters: [::RubyLsp::Yard::Addon::LINTER_ID]}})

        global_state.stub(:settings_for_addon, settings) do
          @addon = ::RubyLsp::Yard::Addon.new
          @addon.activate(global_state, Thread::Queue.new)
        end
        [@addon, global_state]
      end
    end
  end
end
