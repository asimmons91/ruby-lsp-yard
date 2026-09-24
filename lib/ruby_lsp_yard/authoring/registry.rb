# frozen_string_literal: true

module RubyLsp
  module Yard
    module Authoring
      # Holds the activated add-on so the patched host requests can reach its components without depending on
      # `Addon.addons`. Cleared on deactivate, which makes every patch pass through to Ruby LSP (NFR-R2).
      module Registry
        class << self
          attr_accessor :current

          def adapter
            current&.indexer
          end

          def store
            current&.signature_store
          end

          def diagnostics
            current&.diagnostics
          end

          # FR-M5-03: quick fixes need both the diagnostics linter and the code-action patch, so they respect
          # `enableDiagnostics` alongside `enableAuthoring`.
          def diagnostics?
            !!diagnostics && !!current&.settings&.enabled?(:diagnostics)
          end

          def fixes
            return nil unless diagnostics?

            Diagnostics::Fixes.new(
              linter: diagnostics,
              adapter: adapter,
              store: store,
              log: log
            )
          end

          def log
            current&.log
          end

          # FR-M4-02 + NFR-CFG2: authoring features are gated by their own setting; comment hover and definition
          # additionally respect the hover and definition settings.
          def authoring?
            !!current&.settings&.enabled?(:authoring)
          end

          def comment_hover?
            authoring? && current.settings.enabled?(:hover)
          end

          def comment_definition?
            authoring? && current.settings.enabled?(:definition)
          end

          def snippets?
            return false unless current&.settings&.enabled?(:snippets)

            current.snippets?
          end
        end
      end
    end
  end
end
