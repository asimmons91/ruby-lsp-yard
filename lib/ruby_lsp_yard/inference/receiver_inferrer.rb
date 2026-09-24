# frozen_string_literal: true

module RubyLsp
  module Yard
    module Inference
      # Wraps Ruby LSP's own `TypeInferrer` for M1 (FR-M1-12). It resolves the receivers Ruby LSP already handles:
      # `self`, constants, `Foo.new` and guessed locals. The M2 inference engine replaces this behind the same
      # interface, so listeners never touch the host inferrer directly.
      class ReceiverInferrer
        def initialize(type_inferrer = nil)
          @type_inferrer = type_inferrer
        end

        # Returns `[owner, singleton]` for the receiver of the node in `node_context`, or nil when it cannot be
        # inferred. Never raises.
        def owner_for(node_context)
          type = @type_inferrer&.infer_receiver_type(node_context)
          return nil unless type&.name

          normalize(type.name)
        rescue
          nil
        end

        private

        # `FixtureProject::Dog::<Class:Dog>` -> `["FixtureProject::Dog", true]`.
        def normalize(name)
          marker = name.rindex("::<Class:")
          return [name[0...marker], true] if marker && name.end_with?(">")

          [name, false]
        end
      end
    end
  end
end
