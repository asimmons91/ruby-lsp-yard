# frozen_string_literal: true

require "prism"

require_relative "../documentation"
require_relative "../authoring/method_info"
require_relative "../indexer/definition"
require_relative "suppression"
require_relative "target"

module RubyLsp
  module Yard
    module Diagnostics
      # Walks a document's AST once and collects every documented definition as a {Target}: methods, attributes,
      # namespaces and constants, each with the YARD comment block immediately above it (FR-M5-01..04). This runs on
      # the live document, not the indexer, so unsaved buffers are diagnosed correctly. Never raises (NFR-R1).
      class Scanner
        VISIBILITY_CALLS = {
          private: :private,
          protected: :protected,
          public: :public,
          module_function: :public,
          private_class_method: :private
        }.freeze

        ACCESSOR_CALLS = %i[attr_reader attr_writer attr_accessor attr].freeze

        def initialize(document, log: nil)
          @document = document
          @log = log
          @extractor = Documentation::TagExtractor.new(log: log)
          @comment_by_end_line = {}
          @visibility_overrides = {}
          @targets = []
        end

        def targets
          scan unless @scanned
          @targets
        end

        private

        def scan
          @scanned = true
          index_comments
          visit_class_level(@document.ast, [], false, :public)
          resolve_visibility_overrides
          @targets.sort_by { |target| target.location&.start_line || 0 }
        rescue => e
          @log&.error("Diagnostics scan failed: #{e.class}: #{e.message}")
          []
        end

        def index_comments
          @comment_by_end_line = {}
          comments.each do |comment|
            @comment_by_end_line[comment.location.end_line] = comment
          end
        end

        # The host's parsed comment list. Guarded because the shape is an internal detail of `RubyDocument`
        # (the same guarded probe M4 makes; M6 must re-check it).
        def comments
          result = @document.respond_to?(:parse_result) ? @document.parse_result : nil
          list = result&.comments
          list.is_a?(Array) ? list : []
        rescue
          []
        end

        # Walks statements at class/module/program level. Method bodies are not descended into: nested `def`s are
        # dynamic, and the enclosing method's comment does not belong to them.
        def visit_class_level(node, nesting, singleton_context, visibility)
          case node
          when Prism::ProgramNode
            visibility = visit_class_level(node.statements, nesting, singleton_context, visibility)
          when Prism::StatementsNode
            node.body.each { |child| visibility = visit_class_level(child, nesting, singleton_context, visibility) }
          when Prism::ClassNode, Prism::ModuleNode
            child_nesting = nesting + node.constant_path.slice.split("::")
            add_namespace_target(node, child_nesting)
            visit_class_level(node.body, child_nesting, false, :public)
          when Prism::SingletonClassNode
            visit_class_level(node.body, nesting, true, :public)
          when Prism::DefNode
            add_method_target(
              node,
              nesting,
              singleton: singleton_context || node.receiver.is_a?(Prism::SelfNode),
              visibility: visibility
            )
          when Prism::CallNode
            visibility = visit_call(node, nesting, singleton_context, visibility)
          when Prism::ConstantWriteNode, Prism::ConstantPathWriteNode
            add_constant_target(node, nesting)
          end
          visibility
        end

        def visit_call(node, nesting, singleton_context, visibility)
          implicit_receiver = node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

          if implicit_receiver
            return handle_visibility_call(node, nesting, singleton_context, visibility) if VISIBILITY_CALLS.key?(node.name)

            add_attribute_target(node, nesting, singleton_context, visibility) if ACCESSOR_CALLS.include?(node.name)
          end

          # DSL blocks at class level (`included do ... end`, `class_methods do ... end`) contain definitions that
          # belong to the current class.
          block = node.block
          if implicit_receiver && block.is_a?(Prism::BlockNode) && block.body
            visit_class_level(block.body, nesting, singleton_context, visibility)
          end

          visibility
        end

        def handle_visibility_call(node, nesting, singleton_context, visibility)
          arguments = Array(node.arguments&.arguments)
          return VISIBILITY_CALLS[node.name] if arguments.empty?

          declaration = VISIBILITY_CALLS[node.name]
          arguments.each do |argument|
            case argument
            when Prism::DefNode
              add_method_target(
                argument,
                nesting,
                singleton: singleton_context || argument.receiver.is_a?(Prism::SelfNode),
                visibility: declaration
              )
            when Prism::SymbolNode
              singleton = singleton_context || node.name == :private_class_method
              @visibility_overrides[[nesting.join("::"), argument.unescaped, singleton]] = declaration
            end
          end

          visibility
        end

        # --- Target construction -----------------------------------------------------------------------------------

        def add_method_target(node, nesting, singleton:, visibility:)
          build_target(
            node,
            kind: :method,
            nesting: nesting,
            name: node.name.to_s,
            singleton: singleton,
            visibility: visibility,
            parameters: Authoring::MethodInfo.parameters(node),
            location: location_for(node.name_loc || node.location)
          )
        end

        def add_attribute_target(node, nesting, singleton_context, visibility)
          names = Array(node.arguments&.arguments).filter_map do |argument|
            argument.unescaped if argument.is_a?(Prism::SymbolNode)
          end
          return if names.empty?

          build_target(
            node,
            kind: :attribute,
            nesting: nesting,
            attr_names: names,
            singleton: singleton_context,
            visibility: visibility,
            location: location_for(node.message_loc || node.location)
          )
        end

        def add_namespace_target(node, nesting)
          build_target(
            node,
            kind: :namespace,
            nesting: nesting,
            name: nesting.last.to_s,
            location: location_for(node.constant_path.location)
          )
        end

        def add_constant_target(node, nesting)
          if node.is_a?(Prism::ConstantWriteNode)
            location = node.name_loc || node.location
            name = node.name.to_s
          else
            location = node.constant_path&.location || node.location
            name = node.constant_path&.slice.to_s
          end
          build_target(node, kind: :constant, nesting: nesting, name: name, location: location_for(location))
        end

        def build_target(node, kind:, nesting:, name: nil, attr_names: [], singleton: false, visibility: :public,
          parameters: [], location: nil)
          comments = comment_block_for(node.location.start_line)
          return unless comments

          text = text_for(comments)
          return unless text.include?("@")

          @targets << Target.new(
            node: node,
            kind: kind,
            owner: nesting.join("::"),
            nesting: nesting,
            name: name,
            attr_names: attr_names,
            singleton: singleton,
            visibility: visibility,
            parameters: parameters,
            location: location,
            comment_lines: comments.map { |comment| raw_slice(comment) },
            comment_start_line: comments.first.location.start_line,
            comment_text: text,
            raw_doc: @extractor.extract(text),
            suppression: Suppression.parse(comments.map { |comment| raw_slice(comment) })
          )
        end

        # The contiguous run of comments ending on the line immediately before `line`. A comment that follows code
        # on its line does not document the definition below it.
        def comment_block_for(line)
          current = @comment_by_end_line[line - 1]
          return nil unless current

          comments = []
          while current
            comments.unshift(current)
            current = @comment_by_end_line[current.location.start_line - 1]
          end

          trailing?(comments.first) ? nil : comments
        end

        def trailing?(comment)
          start = comment.location.start_character_offset
          line_start = @document.source.rindex("\n", start - 1)
          prefix = @document.source[(line_start ? line_start + 1 : 0)...start].to_s
          !prefix.strip.empty?
        end

        def raw_slice(comment)
          @document.source[comment.location.start_character_offset...comment.location.end_character_offset].to_s
        end

        def text_for(comments)
          comments.map do |comment|
            raw_slice(comment).lines.map do |line|
              line = line.chomp
              if line.start_with?("=begin", "=end")
                ""
              else
                line.sub(/\A#\s?/, "")
              end
            end.join("\n")
          end.join("\n")
        end

        def location_for(location)
          return nil unless location

          Indexer::Location.new(
            start_line: location.start_line,
            start_column: location.start_column,
            end_line: location.end_line,
            end_column: location.end_column
          )
        end

        # `private :foo` can appear after the definition, so overrides are applied once the whole file is known.
        def resolve_visibility_overrides
          @targets.map! do |target|
            next target unless target.kind == :method

            override = @visibility_overrides[[target.owner, target.name, target.singleton]]
            override ? target.with_visibility(override) : target
          end
        end
      end
    end
  end
end
