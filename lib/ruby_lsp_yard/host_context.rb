# frozen_string_literal: true

require "prism"

module RubyLsp
  module Yard
    # Normalizes the `NodeContext` shape differences between Ruby LSP 0.26 and 0.27 so inference and listeners can
    # stay version independent (FR-M6-02):
    #
    # - 0.26: `surrounding_method` is the method name String and `def self.foo` adds a `<Class:Foo>` nesting entry.
    # - 0.27: `surrounding_method` is a `NodeContext::MethodDef` carrying `name` and `receiver`
    #   (`"none"`, `"self"`, a constant name or nil), and singleton nesting entries are named `<Foo>`.
    #
    # Never raises: unknown shapes degrade to nil/false (NFR-R1).
    module HostContext
      module_function

      def surrounding_method_name(node_context)
        method = node_context&.surrounding_method
        return nil unless method

        method.respond_to?(:name) ? method.name : method.to_s
      rescue
        nil
      end

      def surrounding_method_receiver(node_context)
        method = node_context&.surrounding_method
        return method.receiver if method.respond_to?(:receiver)

        # 0.26 stores only the method name; the receiver is recovered from the innermost def node.
        case (receiver = innermost_def_node(node_context)&.receiver)
        when Prism::SelfNode
          "self"
        when Prism::ConstantReadNode, Prism::ConstantPathNode
          receiver.slice
        end
      rescue
        nil
      end

      def innermost_def_node(node_context)
        nodes = node_context&.instance_variable_get(:@nesting_nodes)
        return nil unless nodes.is_a?(Array)

        nodes.reverse_each.find { |node| node.is_a?(Prism::DefNode) }
      rescue
        nil
      end

      # True when `self` is the enclosing class/module object rather than an instance.
      def singleton?(node_context)
        return true if singleton_nesting?(node_context&.nesting)

        receiver = surrounding_method_receiver(node_context)
        !receiver.nil? && receiver != "none"
      rescue
        false
      end

      def singleton_nesting?(nesting)
        Array(nesting).any? { |part| part.to_s.start_with?("<") }
      end

      # The lexical owner name with singleton markers removed.
      def owner(node_context)
        Array(node_context&.nesting).reject { |part| part.to_s.start_with?("<") }.join("::")
      end
    end
  end
end
