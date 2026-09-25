# frozen_string_literal: true

require_relative "../types"

module RubyLsp
  module Yard
    module Inference
      # Reads Solargraph-style inline `# @type [Foo]` annotations from a live document (FR-M2-13, D6). The annotation
      # is the comment block immediately above an assignment and replaces the inferred type of that assignment's
      # value. The live document is used so unsaved buffers are annotated correctly. Never raises: failures degrade
      # to nil (NFR-R1).
      class Annotations
        PATTERN = /\A\s*#\s*@type\s+\[([^\]]*)\]\s*\z/

        def initialize(document, adapter, log: nil)
          @document = document
          @adapter = adapter
          @log = log
          @lines = document.source.lines
          @parsers = {}
        end

        # The annotated type for the assignment node, or nil when the line above it carries no `@type` comment.
        def type_for(node, nesting: [])
          line = (node.respond_to?(:location) && node.location) ? node.location.start_line : nil
          return nil unless line

          text = annotation_text(line)
          return nil if text.nil? || text.empty?

          parser_for(nesting).parse(text)
        rescue => e
          @log&.error("Inline @type annotation failed: #{e.class}: #{e.message}")
          nil
        end

        private

        # The nearest `@type` in the contiguous comment block ending on the line above `line`.
        def annotation_text(line)
          index = line - 2
          while index >= 0
            candidate = @lines[index].to_s
            break unless candidate.match?(/\A\s*#/)

            match = PATTERN.match(candidate)
            return match[1].strip if match

            index -= 1
          end
          nil
        end

        def parser_for(nesting)
          key = Array(nesting).join("::")
          @parsers[key] ||= Types::Parser.new(
            resolver: ->(name, lookup_nesting) { @adapter.resolve_constant(name, lookup_nesting) },
            nesting: Array(nesting)
          )
        end
      end
    end
  end
end
