# frozen_string_literal: true

require "prism"

require_relative "../documentation"
require_relative "method_info"

module RubyLsp
  module Yard
    module Authoring
      # Works out what a cursor inside a comment is positioned on (FR-M4-01): the comment block, the definition the
      # block documents, the lexical nesting and whether the user is typing a tag, a directive, a type, a parameter
      # name or free text. Built once per patched request; never raises (NFR-R1).
      class Context
        Param = MethodInfo::Param

        OWNER_TYPES = [
          Prism::DefNode,
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::CallNode,
          Prism::ConstantWriteNode,
          Prism::ConstantPathWriteNode
        ].freeze

        VISIBILITY_CALLS = %i[private protected public module_function private_class_method].freeze

        TAG_PATTERN = /\A#?\s*(@!?\w*)\z/
        TYPE_PATTERN = /@\w+[^\[]*\[([^\]\n]*)\z/
        PARAM_PATTERN = /@(?:param|yieldparam|option)\s+([\w*&:.]*)\z/
        CONSTANT_PATTERN = /(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*/

        attr_reader :document, :position, :kind, :prefix, :token_range, :line, :nesting, :definition, :raw_doc,
          :tag_name

        # Returns a context when the cursor is inside a comment, nil otherwise. `adapter` is used lazily by the
        # completion and type lookup helpers; it does not need to be set for context-only use.
        def self.build(document, position, adapter: nil, log: nil)
          return nil unless document.respond_to?(:language_id) && document.language_id == :ruby

          new(document, position, adapter: adapter, log: log)
        rescue => e
          log&.error("Authoring context failed: #{e.class}: #{e.message}")
          nil
        end

        # The lexical class/module nesting at `target`, used to prefill skeleton types (FR-M4-06).
        def self.nesting_at(document, target)
          found = nil
          walk = lambda do |node, current|
            return if found

            if node.equal?(target)
              found = current
              return
            end

            child_nesting = current
            if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
              child_nesting = current + [node.constant_path.slice]
            end
            node.compact_child_nodes.each { |child| walk.call(child, child_nesting) }
          end
          walk.call(document.ast, [])
          found || []
        rescue
          []
        end

        def initialize(document, position, adapter: nil, log: nil)
          @document = document
          @position = position
          @adapter = adapter
          @log = log
          @line = Integer(position[:line] || position["line"])
          @character = Integer(position[:character] || position["character"])
          @cursor_offset = document.find_index_by_position(position).first
          @comments = comments
          @comment = covering_comment
          raise "not a comment" unless @comment

          @block = comment_block
          @before = last_line_before
          @comment_text = @block.map { |comment| stripped(comment) }.join("\n")
          @raw_doc = Documentation::TagExtractor.new(log: log).extract(@comment_text)
          @kind, token_index, @prefix = classify(@before)
          @tag_name = @before.scan(/@!?(\w+)/).last&.first
          @token_range = range_for(token_index)
          @nesting, @definition = locate_definition
        end

        def comment?
          true
        end

        def attached?
          !@definition.nil?
        end

        # A comment that follows code on its line does not document a definition below it.
        def trailing?
          start = @comment.location.start_character_offset
          line_start = document.source.rindex("\n", start - 1)
          prefix = document.source[(line_start ? line_start + 1 : 0)...start].to_s
          !prefix.strip.empty?
        end

        def def_node
          @definition.is_a?(Prism::DefNode) ? @definition : nil
        end

        def singleton?
          receiver = def_node&.receiver
          receiver.is_a?(Prism::SelfNode) || @definition.is_a?(Prism::SingletonClassNode)
        end

        # The name of the documented namespace or method, used for signature prefill.
        def definition_name
          def_node&.name.to_s
        end

        def owner_name
          @nesting.empty? ? nil : @nesting.join("::")
        end

        # Parameters of the documented method, in source order. Empty when the definition is not a method.
        def parameters
          @parameters ||= MethodInfo.parameters(def_node)
        end

        # Parameter names already documented in the comment block, with sigils stripped.
        def documented_params
          @documented_params ||= @raw_doc.params.map do |param|
            param.name.to_s.sub(/\A[*&:]+/, "").sub(/:\z/, "")
          end
        end

        # FR-M4-03: yield tags are only suggested for methods that yield or take a block.
        def yields?
          return @yields if defined?(@yields)

          @yields = MethodInfo.yields?(def_node)
        end

        # FR-M4-03: the class from the first `raise SomeError` in the body, if any.
        def raise_class
          return @raise_class if defined?(@raise_class)

          @raise_class = MethodInfo.raise_class(def_node)
        end

        # The constant path the cursor is on, for comment hover and definition (FR-M1-14, FR-M4-P6).
        def constant_at_cursor
          line_text = document.source.lines[@line].to_s
          offset = @character
          line_text.to_enum(:scan, CONSTANT_PATTERN).map { Regexp.last_match }.find do |match|
            offset.between?(match.begin(0), match.end(0))
          end&.to_s
        end

        # Resolves the constant under the cursor relative to the documented definition's nesting.
        def resolve_constant(name)
          return nil unless @adapter

          @adapter.resolve_constant(name, @nesting)
        end

        private

        def comments
          result = @document.instance_variable_get(:@parse_result)
          comments = result&.comments
          comments.is_a?(Array) ? comments : nil
        rescue
          nil
        end

        def covering_comment
          return nil unless @comments

          @comments.find do |comment|
            location = comment.location
            start_offset = location.start_character_offset
            end_offset = location.end_character_offset
            @cursor_offset.between?(start_offset, end_offset)
          end
        end

        # The contiguous run of comments around the cursor, so tags above the cursor count as documented (FR-M4-03).
        def comment_block
          index = @comments.index(@comment)
          block = [@comment]
          candidate = index - 1
          while candidate >= 0 && @comments[candidate].location.end_line + 1 == block.first.location.start_line
            block.unshift(@comments[candidate])
            candidate -= 1
          end
          candidate = index + 1
          while candidate < @comments.length && block.last.location.end_line + 1 == @comments[candidate].location.start_line
            block << @comments[candidate]
            candidate += 1
          end
          block
        end

        def stripped(comment)
          slice = document.source[comment.location.start_character_offset...comment.location.end_character_offset].to_s
          slice.lines.map do |line|
            line = line.chomp
            if line.start_with?("=begin", "=end")
              ""
            else
              line.sub(/\A#\s?/, "")
            end
          end.join("\n")
        end

        def last_line_before
          start = @comment.location.start_character_offset
          document.source[start...@cursor_offset].to_s.split("\n", -1).last.to_s
        end

        def classify(before)
          if (match = before.match(TAG_PATTERN))
            kind = (before[match.begin(1), 2] == "@!") ? :directive : :tag
            return [kind, match.begin(1), match[1]]
          end
          if (match = before.match(TYPE_PATTERN))
            return [:type, match.begin(1), match[1]]
          end
          if (match = before.match(PARAM_PATTERN))
            return [:param, match.begin(1), match[1]]
          end

          [:free_text, before.length, ""]
        end

        def range_for(token_index)
          start_column = @character - (@before.length - token_index)
          Interface::Range.new(
            start: Interface::Position.new(line: @line, character: [start_column, 0].max),
            end: Interface::Position.new(line: @line, character: @character)
          )
        end

        def locate_definition
          return [[], nil] if trailing?

          code_line = document.source.lines[@block.last.location.end_line]
          return [[], nil] if code_line.nil? || code_line.strip.empty? || code_line.lstrip.start_with?("#")

          start_line = @block.last.location.end_line + 1
          found = nil
          nesting = []
          walk = lambda do |node, current_nesting|
            return if found || node.location.start_line > start_line

            if node.location.start_line == start_line && OWNER_TYPES.any? { |type| node.is_a?(type) }
              unless bare_visibility_call?(node)
                found = node
                nesting = current_nesting
                return
              end
            end

            child_nesting = current_nesting
            if node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)
              child_nesting = current_nesting + [node.constant_path.slice]
            end
            node.compact_child_nodes.each { |child| walk.call(child, child_nesting) }
          end
          walk.call(document.ast, [])
          [nesting, found]
        end

        def bare_visibility_call?(node)
          node.is_a?(Prism::CallNode) && node.receiver.nil? && VISIBILITY_CALLS.include?(node.name)
        end
      end
    end
  end
end
