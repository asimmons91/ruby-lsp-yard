# frozen_string_literal: true

module RubyLsp
  module Yard
    module Diagnostics
      # A documented definition found by the scanner: the node, the YARD docstring attached to it and the lexical
      # information rules need to resolve types. Lines are 1-based, columns 0-based, matching Prism and the indexer
      # (FR-M5-01..04).
      class Target
        attr_reader :node, :kind, :name, :attr_names, :singleton, :owner, :nesting, :visibility,
          :parameters, :location, :comment_lines, :comment_start_line, :comment_text, :raw_doc, :suppression

        # `node`: the Prism definition node. `kind`: :method, :attribute, :namespace or :constant.
        # `location`: an {Indexer::Location} or nil when the node carries no usable range.
        def initialize(
          node:,
          kind:,
          owner: "",
          nesting: [],
          name: nil,
          attr_names: [],
          singleton: false,
          visibility: :public,
          parameters: [],
          location: nil,
          comment_lines: [],
          comment_start_line: 0,
          comment_text: "",
          raw_doc: nil,
          suppression: nil
        )
          @node = node
          @kind = kind
          @owner = owner
          @nesting = nesting
          @name = name
          @attr_names = attr_names
          @singleton = singleton
          @visibility = visibility
          @parameters = parameters
          @location = location
          @comment_lines = comment_lines
          @comment_start_line = comment_start_line
          @comment_text = comment_text
          @raw_doc = raw_doc
          @suppression = suppression
        end

        def documented?
          !@raw_doc.nil? && !@raw_doc.empty?
        end

        def def_node?
          @node.is_a?(Prism::DefNode)
        end

        def suppressed?(rule_key)
          @suppression ? @suppression.suppressed?(rule_key) : false
        end

        # A copy with a different visibility, used when `private :name` appears after the definition.
        def with_visibility(visibility)
          copy = dup
          copy.instance_variable_set(:@visibility, visibility)
          copy
        end
      end
    end
  end
end
