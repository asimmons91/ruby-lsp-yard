# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/addon"
require "uri"

require_relative "../../ruby_lsp_yard/indexer"
require_relative "../../ruby_lsp_yard/log"
require_relative "../../ruby_lsp_yard/settings"
require_relative "../../ruby_lsp_yard/version"

RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")

module RubyLsp
  module Yard
    class Addon < ::RubyLsp::Addon
      attr_reader :settings, :indexer, :log

      def activate(global_state, outgoing_queue)
        @settings = Settings.new(global_state.settings_for_addon(name))
        @log = Log.new(outgoing_queue, level: settings.log_level)
        @indexer = Indexer.for(global_state, log: log)
        @log.debug("Activated with Ruby LSP #{RubyLsp::VERSION}")
      rescue => e
        add_error(e)
        @log&.error("Failed to activate: #{e.class}: #{e.message}")
      end

      def deactivate
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

      def name
        "Ruby LSP YARD"
      end

      def version
        VERSION
      end
    end
  end
end
