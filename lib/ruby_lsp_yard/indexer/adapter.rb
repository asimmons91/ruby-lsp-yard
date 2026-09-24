# frozen_string_literal: true

module RubyLsp
  module Yard
    module Indexer
      # The only interface the add-on uses to talk to the host indexer (FR-M0-03). Implementations must never raise
      # out of these methods: missing entries, invalid names and backend errors degrade to `nil` or `[]` (NFR-R1).
      class Adapter
        def initialize(log: nil)
          @log = log
          @subscribers = []
        end

        # Registers a callback invoked with the changed URIs whenever {#on_change} is called. Returns the callback.
        def subscribe(&block)
          @subscribers << block
          block
        end

        # Called by the add-on when watched files change so that consumers can invalidate memoized data.
        def on_change(uris)
          changed = Array(uris).compact
          return if changed.empty?

          @subscribers.each do |subscriber|
            subscriber.call(changed)
          rescue => e
            @log&.error("Indexer on_change subscriber failed: #{e.class}: #{e.message}")
          end
        end

        # Returns the definitions of `name` on `owner` (or its ancestors) as `Definition` structs. Singleton methods
        # live on the owner's singleton class.
        def method_definitions(owner, name, singleton: false)
          raise NotImplementedError
        end

        # Returns the reader/writer definitions for the attribute `name` on `owner` or its ancestors.
        def attribute_definitions(owner, name)
          raise NotImplementedError
        end

        # Returns the constant, class and module definitions named `name` (fully qualified), including their
        # comments. Used to find `@!method`, `@!attribute` and `@!parse` directives on namespaces.
        def constant_definitions(name)
          raise NotImplementedError
        end

        # Resolves a possibly unqualified constant reference relative to `nesting` and returns its fully qualified
        # name, or nil when it cannot be resolved.
        def resolve_constant(name, nesting)
          raise NotImplementedError
        end

        # Returns the linearized ancestors of a fully qualified name, including modules, or `[]` when unknown.
        def ancestors(fully_qualified_name)
          raise NotImplementedError
        end

        # Returns the methods available on `owner`, optionally filtered by `prefix`, as `Definition` structs.
        # Implementations may read comments here, since callers use them for directive discovery.
        def methods_of(owner, prefix: nil, singleton: false)
          raise NotImplementedError
        end

        # Like {#methods_of}, but for completion candidate display. Implementations must not read comments: the
        # candidate set can be large and reading comments re-parses the owning file for every entry.
        def completion_candidates(owner, prefix: nil, singleton: false)
          raise NotImplementedError
        end

        # Returns the constants, classes and modules whose name starts with `prefix`, resolved relative to `nesting`,
        # as `Definition` structs. Used by type completion inside YARD comments (FR-M4-05). Implementations must not
        # read comments: the candidate set can be large.
        def constant_candidates(prefix, nesting)
          raise NotImplementedError
        end
      end
    end
  end
end
