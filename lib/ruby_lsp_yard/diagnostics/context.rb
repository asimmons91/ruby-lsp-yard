# frozen_string_literal: true

require_relative "../types"
require_relative "../indexer/definition"

module RubyLsp
  module Yard
    module Diagnostics
      # Per-request state rules share: the type parser bound to a target's nesting, constant resolution and range
      # helpers that locate a tag inside the comment block or fall back to the definition's name (FR-M5-01..04).
      class Context
        attr_reader :document, :adapter, :store, :inference, :budget, :log, :targets

        def initialize(document:, adapter: nil, store: nil, inference: nil, budget: nil, log: nil, targets: [])
          @document = document
          @adapter = adapter
          @store = store
          @inference = inference
          @budget = budget
          @log = log
          @targets = targets
          @parsers = {}
        end

        # A type parser whose resolver and nesting match the documented definition, so relative type names resolve
        # the same way the signature store resolves them (FR-M1-08).
        def parser(target)
          @parsers[target.nesting] ||= Types::Parser.new(
            resolver: resolver,
            nesting: target.nesting
          )
        end

        def resolve(name, target)
          return nil unless @adapter

          @adapter.resolve_constant(name, target.nesting)
        rescue
          nil
        end

        # The range of `text` inside the target's comment block, or the fallback (the definition itself) when the
        # text cannot be located verbatim.
        def range_for_text(target, text, fallback: nil)
          needle = text.to_s
          unless needle.empty?
            target.comment_lines.each_with_index do |raw, offset|
              index = raw.index(needle)
              next unless index

              line = target.comment_start_line - 1 + offset
              # Comment slices start at `#`; add the line's indentation so the range matches the file.
              indent = document.source.lines[line].to_s.index("#").to_i
              return lsp_range(line, indent + index, indent + index + needle.length)
            end
          end

          fallback ||= target.location
          fallback.is_a?(Interface::Range) ? fallback : range_for_location(fallback)
        end

        def range_for_location(location)
          return nil unless location

          Interface::Range.new(
            start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
            end: Interface::Position.new(line: location.end_line - 1, character: location.end_column)
          )
        end

        # The range of a Prism location, so document-wide rules can point at nodes.
        def prism_range(location)
          return nil unless location

          range_for_location(
            Indexer::Location.new(
              start_line: location.start_line,
              start_column: location.start_column,
              end_line: location.end_line,
              end_column: location.end_column
            )
          )
        end

        # The range of the tag named in `tag` (e.g. `@param key`), used when a type string cannot be located.
        def tag_range(target, tag)
          range_for_text(target, tag, fallback: target.location)
        end

        # The range of a {TypeWalker::TypeRef}: the type text when it appears verbatim in the comment block,
        # otherwise its tag.
        def type_range(target, ref)
          range_for_text(target, ref.text, fallback: tag_range(target, ref.tag))
        end

        # The adapter's constant resolver as a `(name, nesting) -> fully_qualified_name | nil` callable, or nil when
        # no adapter is available. `TypeWalker` and the type parsers consume this shape.
        def resolver
          return @resolver if defined?(@resolver)

          adapter = @adapter
          @resolver = adapter ? ->(name, nesting) { adapter.resolve_constant(name, nesting) } : nil
        end

        private

        def lsp_range(line, start_character, end_character)
          Interface::Range.new(
            start: Interface::Position.new(line: line, character: start_character),
            end: Interface::Position.new(line: line, character: end_character)
          )
        end
      end
    end
  end
end
