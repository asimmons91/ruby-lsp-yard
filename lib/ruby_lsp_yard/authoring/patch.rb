# frozen_string_literal: true

require_relative "comment_completion"
require_relative "context"
require_relative "registry"
require_relative "skeleton"
require_relative "type_lookup"

module RubyLsp
  module Yard
    module Authoring
      # The comment-reaching monkeypatch decided in D3 (FR-M4-P1..P6). All prepended modules live in this file so a
      # Ruby LSP upgrade can be reviewed quickly (FR-M4-P5). Each module notes the exact upstream method it wraps:
      #
      #   RubyLsp::Requests::Completion#initialize/#perform   (lib/ruby_lsp/requests/completion.rb)
      #   RubyLsp::Requests::Hover#initialize/#perform        (lib/ruby_lsp/requests/hover.rb)
      #   RubyLsp::Requests::Definition#initialize/#perform   (lib/ruby_lsp/requests/definition.rb)
      #   RubyLsp::Requests::CodeActions#perform              (lib/ruby_lsp/requests/code_actions.rb)
      #   RubyLsp::ClientCapabilities#apply_client_capabilities (lib/ruby_lsp/client_capabilities.rb)
      #
      # M5 extends the `CodeActions` patch with diagnostics quick fixes (FR-M5-03).
      #
      # The patch is only applied to the versions listed in {TESTED_VERSIONS} (FR-M4-P2). Any exception inside a
      # patched method falls back to the original behavior (FR-M4-P4, NFR-R2).
      module Patch
        TESTED_VERSIONS = %w[0.26.11 0.27.0.beta5].freeze

        PATCHED_METHODS = {
          "RubyLsp::Requests::Completion" => %i[initialize perform],
          "RubyLsp::Requests::Hover" => %i[initialize perform],
          "RubyLsp::Requests::Definition" => %i[initialize perform],
          "RubyLsp::Requests::CodeActions" => %i[perform],
          "RubyLsp::ClientCapabilities" => %i[apply_client_capabilities]
        }.freeze

        class << self
          def install!
            return true if @installed
            return false unless supported_version?

            RubyLsp::Requests::Completion.prepend(CompletionPatch)
            RubyLsp::Requests::Hover.prepend(HoverPatch)
            RubyLsp::Requests::Definition.prepend(DefinitionPatch)
            RubyLsp::Requests::CodeActions.prepend(CodeActionsPatch)
            RubyLsp::ClientCapabilities.prepend(ClientCapabilitiesPatch)
            @installed = true
          end

          def installed?
            !!@installed
          end

          def supported_version?(version = RubyLsp::VERSION)
            TESTED_VERSIONS.include?(version)
          end
        end

        # FR-M4-P1/P3: completion inside a comment returns the authoring items; every other request passes through.
        module CompletionPatch
          def initialize(document, global_state, params, sorbet_level, dispatcher)
            items = yard_comment_items(document, params)
            if items
              @yard_comment_items = items
              return
            end

            super
          end

          def perform
            return @yard_comment_items if defined?(@yard_comment_items) && @yard_comment_items

            super
          end

          private

          def yard_comment_items(document, params)
            return nil unless Registry.authoring?

            position = params[:position] || params["position"]
            return nil unless position

            context = Context.build(document, position, adapter: Registry.adapter, log: Registry.log)
            return nil unless context

            CommentCompletion.new(
              context,
              adapter: Registry.adapter,
              snippets: Registry.snippets?,
              log: Registry.log
            ).items
          rescue => e
            Registry.log&.error("Comment completion patch failed: #{e.class}: #{e.message}")
            nil
          end
        end

        # FR-M4-P6: hover on a type name inside a comment shows the class's documentation.
        module HoverPatch
          def initialize(document, global_state, position, dispatcher, sorbet_level)
            hover = yard_comment_hover(document, position)
            if hover
              @yard_comment_hover = hover
              return
            end

            super
          end

          def perform
            return @yard_comment_hover if defined?(@yard_comment_hover) && @yard_comment_hover

            super
          end

          private

          def yard_comment_hover(document, position)
            return nil unless Registry.comment_hover?

            context = Context.build(document, position, adapter: Registry.adapter, log: Registry.log)
            return nil unless context

            markdown = TypeLookup.new(context, adapter: Registry.adapter, log: Registry.log).hover_markdown
            return nil unless markdown

            Interface::Hover.new(contents: Interface::MarkupContent.new(kind: "markdown", value: markdown))
          rescue => e
            Registry.log&.error("Comment hover patch failed: #{e.class}: #{e.message}")
            nil
          end
        end

        # FR-M4-P6: go to definition on a type name inside a comment jumps to the class.
        module DefinitionPatch
          def initialize(document, global_state, position, dispatcher, sorbet_level)
            links = yard_comment_links(document, position)
            if links
              @yard_comment_links = links
              return
            end

            super
          end

          def perform
            return @yard_comment_links if defined?(@yard_comment_links) && @yard_comment_links

            super
          end

          private

          def yard_comment_links(document, position)
            return nil unless Registry.comment_definition?

            context = Context.build(document, position, adapter: Registry.adapter, log: Registry.log)
            return nil unless context

            lookup = TypeLookup.new(context, adapter: Registry.adapter, log: Registry.log)
            return nil unless lookup.resolved

            links = lookup.links
            links.empty? ? nil : links
          rescue => e
            Registry.log&.error("Comment definition patch failed: #{e.class}: #{e.message}")
            nil
          end
        end

        # FR-M4-06: no add-on hook exists for code actions, so the skeleton action is appended to the host response.
        # FR-M5-03 adds the diagnostics quick fixes through the same patch.
        module CodeActionsPatch
          def perform
            actions = super
            return actions unless Registry.authoring?

            action = yard_skeleton_action
            actions += [action] if action
            actions + yard_quick_fix_actions
          end

          private

          # FR-M5-03: recompute the fixable diagnostics for this document and turn the ones in the requested range
          # into quick-fix actions.
          def yard_quick_fix_actions
            fixes = Registry.fixes
            return [] unless fixes

            fixes.actions_for(document: @document, uri: @document.uri, range: @range)
          rescue => e
            Registry.log&.error("Quick fix actions failed: #{e.class}: #{e.message}")
            []
          end

          def yard_skeleton_action
            return nil unless @document.respond_to?(:language_id) && @document.language_id == :ruby

            node = locate_def
            return nil unless node
            return nil if documented?(node)

            skeleton = Skeleton.new(
              def_node: node,
              nesting: Context.nesting_at(@document, node),
              document: @document,
              store: Registry.store
            )
            Interface::CodeAction.new(
              title: "Add YARD documentation",
              kind: Constant::CodeActionKind::REFACTOR_REWRITE,
              edit: Interface::WorkspaceEdit.new(changes: {@document.uri.to_s => [skeleton.edit]})
            )
          rescue => e
            Registry.log&.error("Skeleton code action failed: #{e.class}: #{e.message}")
            nil
          end

          def locate_def
            start = @range[:start]
            return nil unless start

            if start != @range[:end]
              @document.locate_first_within_range(@range, node_types: [Prism::DefNode])
            else
              node = @document.locate_node(start, node_types: [Prism::DefNode]).node
              node.is_a?(Prism::DefNode) ? node : nil
            end
          rescue
            nil
          end

          def documented?(node)
            start_line = node.location.start_line
            return false if start_line <= 1

            line = @document.source.lines[start_line - 2]
            !line.nil? && line.lstrip.start_with?("#")
          end
        end

        # Records `completionItem.snippetSupport` so the authoring completion can degrade to plain text (NFR-C3).
        # Ruby LSP 0.26 keeps only the capability flags it uses, so this mirrors one extra flag.
        module ClientCapabilitiesPatch
          def apply_client_capabilities(capabilities)
            @supports_snippets = begin
              capabilities.dig(:textDocument, :completion, :completionItem, :snippetSupport) || false
            rescue
              false
            end
            super
          end

          # nil when capabilities were never observed (Ruby LSP 0.26 applies them before add-ons load).
          def supports_snippets
            @supports_snippets
          end
        end
      end
    end
  end
end
