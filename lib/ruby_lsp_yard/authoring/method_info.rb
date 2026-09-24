# frozen_string_literal: true

require "prism"

module RubyLsp
  module Yard
    module Authoring
      # Static facts about a `def` node that both comment context detection and skeleton generation need (FR-M4-03,
      # FR-M4-06): its parameters, whether it yields and the class of the first `raise` in its body.
      module MethodInfo
        # A parameter of a method definition. `kind` matches {Indexer::Parameter}.
        Param = Struct.new(:name, :kind)

        module_function

        def parameters(def_node)
          parameters = def_node&.parameters
          return [] unless parameters

          list = []
          parameters.requireds.each { |node| append(list, node, :required) }
          parameters.optionals.each { |node| append(list, node, :optional) }
          append(list, parameters.rest, :rest)
          parameters.posts.each { |node| append(list, node, :required) }
          parameters.keywords.each do |node|
            append(list, node, node.is_a?(Prism::OptionalKeywordParameterNode) ? :keyword_optional : :keyword)
          end
          append(list, parameters.keyword_rest, :keyword_rest)
          append(list, parameters.block, :block)
          list
        end

        # Destructured (`(a, b)`) and anonymous (`*`, `**`, `&`) parameters have no usable name and are skipped.
        def append(list, node, kind)
          return unless node

          name = node.respond_to?(:name) ? node.name : nil
          list << Param.new(name.to_s, kind) if name && !name.to_s.empty?
        end

        # FR-M4-03: yield tags are suggested when the method contains `yield` or takes a block.
        def yields?(def_node)
          return false unless def_node

          !def_node.parameters&.block.nil? || contains?(def_node, Prism::YieldNode)
        end

        # The class name from the first `raise SomeError` in the body, or nil.
        def raise_class(def_node)
          each_body_node(def_node) do |node|
            next unless node.is_a?(Prism::CallNode) && node.name == :raise
            next if node.receiver && !node.receiver.is_a?(Prism::SelfNode)

            argument = node.arguments&.arguments&.first
            case argument
            when Prism::ConstantReadNode, Prism::ConstantPathNode
              return argument.slice
            end
          end
          nil
        end

        def contains?(def_node, type)
          each_body_node(def_node) { |node| return true if node.is_a?(type) }
          false
        end

        def each_body_node(def_node)
          body = def_node&.body
          return unless body

          stack = [body]
          until stack.empty?
            node = stack.pop
            yield node
            node.compact_child_nodes.each { |child| stack << child }
          end
        end
      end
    end
  end
end
