# frozen_string_literal: true

module RubyLsp
  module Yard
    module Listeners
      # Cooperates with the host listeners through the shared response builder. Ruby LSP hands the same builder to its
      # own listener and to the add-on's, and `CollectionResponseBuilder#response` exposes the mutable item array, so
      # an add-on that runs later can replace untyped host items with enriched ones (FR-M2-17, FR-M2-19). The shape is
      # probed per request; when it is not a mutable array the listeners fall back to non-destructive behavior
      # (NFR-R1).
      module Responses
        def response_items
          items = @response_builder.response
          items.is_a?(Array) ? items : []
        rescue
          []
        end

        def prune_supported?
          return @prune_supported unless @prune_supported.nil?

          items = @response_builder.response
          @prune_supported = items.is_a?(Array) && !items.frozen?
        rescue
          @prune_supported = false
        end

        # Removes every response item matching the block. Returns true when the builder supports pruning.
        def prune_response_items
          return false unless prune_supported?

          response_items.reject! { |item| yield(item) }
          true
        rescue
          false
        end
      end
    end
  end
end
