# frozen_string_literal: true

require "ruby-lsp"

require_relative "indexer/adapter"
require_relative "indexer/definition"

# Ruby LSP 0.27 replaced `RubyIndexer` with Rubydex (FR-M6-01). Only one backend is available per host, so the
# adapter for the other is neither defined nor required.
if Gem::Version.new(RubyLsp::VERSION) >= Gem::Version.new("0.27.0.a")
  require_relative "indexer/rubydex_adapter"
else
  require_relative "indexer/ruby_indexer_adapter"
end

module RubyLsp
  module Yard
    module Indexer
      # Builds the Indexer Adapter for the running Ruby LSP version. The Rubydex backend for 0.27 keeps the adapter
      # the only code that knows about the host indexer (FR-M6-01).
      def self.for(global_state, log: nil)
        if rubydex?
          RubydexAdapter.new(global_state.graph, log: log)
        else
          RubyIndexerAdapter.new(global_state.index, log: log)
        end
      end

      # Wraps an already-built host index or graph. Used by tests and benchmarks so they do not have to know which
      # backend is active (FR-M6-04).
      def self.wrap(backend, log: nil)
        if rubydex?
          RubydexAdapter.new(backend, log: log)
        else
          RubyIndexerAdapter.new(backend, log: log)
        end
      end

      # True when the Rubydex backend is the active one.
      def self.rubydex?
        defined?(RubydexAdapter) ? true : false
      end

      # The adapter class for the running backend.
      def self.adapter_class
        defined?(RubydexAdapter) ? RubydexAdapter : RubyIndexerAdapter
      end
    end
  end
end
