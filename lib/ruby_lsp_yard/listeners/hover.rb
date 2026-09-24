# frozen_string_literal: true

module RubyLsp
  module Yard
    module Listeners
      # Adds a typed YARD signature to hover responses (FR-M1-12). Ruby LSP dispatches only the hovered node
      # (`dispatch_once`), so only the call node needs handling. Never raises out of the request (NFR-R2).
      class Hover
        def initialize(response_builder, node_context, dispatcher, store:, engine:, log: nil)
          @response_builder = response_builder
          @node_context = node_context
          @store = store
          @engine = engine
          @log = log

          dispatcher.register(self, :on_call_node_enter)
        end

        def on_call_node_enter(node)
          message = node.message
          return unless message

          owner, singleton = @engine.owner_for(@node_context)
          return unless owner

          signature = @store.lookup(owner, message, singleton: singleton)
          return unless signature&.renderable?

          @response_builder.push(signature.to_markdown, category: :title)
        rescue => e
          @log&.error("Hover listener failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
