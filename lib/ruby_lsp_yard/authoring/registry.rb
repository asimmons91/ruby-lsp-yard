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
