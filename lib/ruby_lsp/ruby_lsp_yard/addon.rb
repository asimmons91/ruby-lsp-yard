# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/addon"
require "uri"

require_relative "../../ruby_lsp_yard/gems"
require_relative "../../ruby_lsp_yard/indexer"
require_relative "../../ruby_lsp_yard/inference"
require_relative "../../ruby_lsp_yard/listeners/completion"
require_relative "../../ruby_lsp_yard/listeners/definition"
require_relative "../../ruby_lsp_yard/listeners/hover"
require_relative "../../ruby_lsp_yard/log"
require_relative "../../ruby_lsp_yard/rbs"
require_relative "../../ruby_lsp_yard/settings"
require_relative "../../ruby_lsp_yard/signature_store"
require_relative "../../ruby_lsp_yard/version"

RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")

module RubyLsp
  module Yard
    class Addon < ::RubyLsp::Addon
      attr_reader :settings, :indexer, :signature_store, :inference, :log, :rbs_loader, :rbs_source, :gem_cache

      def activate(global_state, outgoing_queue)
        @settings = Settings.new(global_state.settings_for_addon(name))
        @log = Log.new(outgoing_queue, level: settings.log_level)
        @indexer = Indexer.for(global_state, log: log)
        @rbs_loader = build_rbs_loader
        @rbs_source = Rbs::Source.new(@rbs_loader, log: @log) if @rbs_loader
        @gem_cache = Gems::Cache.new(locator: Gems::Locator.new, log: @log)
        @signature_store = SignatureStore.new(@indexer, log: log, rbs: @rbs_source, gem_cache: @gem_cache)
        @inference = Inference::Engine.new(
          adapter: @indexer,
          store: @signature_store,
          host: global_state.type_inferrer,
          log: log,
          debug: settings.debug_inference?
        )
        @log.debug("Activated with Ruby LSP #{RubyLsp::VERSION}")
      rescue => e
        add_error(e)
        @log&.error("Failed to activate: #{e.class}: #{e.message}")
      end

      def deactivate
        @gem_cache&.flush
        @rbs_loader&.cancel
        @rbs_loader = nil
        @rbs_source = nil
        @gem_cache = nil
        @inference = nil
        @signature_store = nil
        @indexer = nil
        @settings = nil
        @log = nil
      end

      # Ruby LSP registers file watcher add-ons by checking for this method, then forwards watched file changes
      # to it. The adapter notifies its subscribers so cached data can be invalidated.
      def workspace_did_change_watched_files(changes)
        uris = Array(changes).filter_map do |change|
          value = change[:uri] || change["uri"]
          URI(value) if value
        rescue URI::InvalidURIError
          nil
        end

        @indexer&.on_change(uris)
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        return unless settings&.enabled?(:hover)
        return unless @signature_store && @inference

        Listeners::Hover.new(
          response_builder,
          node_context,
          dispatcher,
          engine: @inference,
          log: @log
        )
      end

      def create_completion_listener(response_builder, node_context, dispatcher, _uri)
        return unless settings&.enabled?(:completion)
        return unless @indexer && @signature_store && @inference

        Listeners::Completion.new(
          response_builder,
          node_context,
          dispatcher,
          adapter: @indexer,
          store: @signature_store,
          inference: @inference,
          log: @log
        )
      end

      def create_definition_listener(response_builder, _uri, node_context, dispatcher)
        return unless settings&.enabled?(:definition)
        return unless @indexer && @inference

        Listeners::Definition.new(
          response_builder,
          node_context,
          dispatcher,
          adapter: @indexer,
          inference: @inference,
          log: @log
        )
      end

      # NFR-P1: core/stdlib signatures load in the background; features that need them degrade to YARD until ready.
      def build_rbs_loader
        return nil unless settings.enabled?(:core_types)

        loader = Rbs::Loader.new(log: @log)
        loader.start
        loader
      end

      def name
        "Ruby LSP YARD"
      end

      def version
        VERSION
      end
    end
  end
end
