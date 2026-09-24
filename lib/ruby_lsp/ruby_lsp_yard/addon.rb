# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/addon"
require "uri"

require_relative "../../ruby_lsp_yard/indexer"
require_relative "../../ruby_lsp_yard/inference/receiver_inferrer"
require_relative "../../ruby_lsp_yard/listeners/hover"
require_relative "../../ruby_lsp_yard/log"
require_relative "../../ruby_lsp_yard/settings"
require_relative "../../ruby_lsp_yard/signature_store"
require_relative "../../ruby_lsp_yard/version"

RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")

module RubyLsp
  module Yard
    class Addon < ::RubyLsp::Addon
      attr_reader :settings, :indexer, :signature_store, :receiver_inferrer, :log

      def activate(global_state, outgoing_queue)
        @settings = Settings.new(global_state.settings_for_addon(name))
        @log = Log.new(outgoing_queue, level: settings.log_level)
        @indexer = Indexer.for(global_state, log: log)
        @signature_store = SignatureStore.new(@indexer, log: log)
        @receiver_inferrer = Inference::ReceiverInferrer.new(global_state.type_inferrer)
        @log.debug("Activated with Ruby LSP #{RubyLsp::VERSION}")
      rescue => e
        add_error(e)
        @log&.error("Failed to activate: #{e.class}: #{e.message}")
      end

      def deactivate
        @receiver_inferrer = nil
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
        return unless @signature_store && @receiver_inferrer

        Listeners::Hover.new(
          response_builder,
          node_context,
          dispatcher,
          store: @signature_store,
          inferrer: @receiver_inferrer,
          log: @log
        )
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
