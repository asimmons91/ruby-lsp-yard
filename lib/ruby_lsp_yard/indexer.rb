# frozen_string_literal: true

require_relative "indexer/adapter"
require_relative "indexer/definition"
require_relative "indexer/ruby_indexer_adapter"

module RubyLsp
  module Yard
    module Indexer
      # Builds the Indexer Adapter for the running Ruby LSP version. The Rubydex backend for 0.27 is added in M6
      # (FR-M6-01), keeping the adapter the only code that knows about the host indexer.
      def self.for(global_state, log: nil)
        RubyIndexerAdapter.new(global_state.index, log: log)
      end
    end
  end
end
