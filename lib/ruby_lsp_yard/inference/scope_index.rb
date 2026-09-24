# frozen_string_literal: true

require "prism"

module RubyLsp
  module Yard
    module Inference
      # Gives the inference engine access to the document's AST around the request. Ruby LSP 0.26's NodeContext keeps
      # the Prism nodes from the Program down to the innermost class/module/def/block in the private `@nesting_nodes`
      # array, which is the only way to reach sibling statements such as local assignments (FR-M2-05, FR-M2-08).
      # The accessor is version-guarded: when the shape changes, {#available?} is false and inference degrades to
      # Unknown instead of raising (NFR-R1, M6 must re-check this).
      class ScopeIndex
        # Blocks share the enclosing local scope, so they are not boundaries; everything else is. Lambdas are
        # boundaries too, but can still read the locals of the scopes that enclose them (closures).
        LOCAL_SCOPE_BOUNDARIES = [
          Prism::DefNode,
          Prism::LambdaNode,
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::ProgramNode
        ].freeze
        NESTED_LOCAL_SCOPES = [
          Prism::DefNode,
          Prism::ClassNode,
          Prism::ModuleNode,
          Prism::SingletonClassNode,
          Prism::LambdaNode
        ].freeze
        CLASS_SCOPES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze

        def self.nesting_nodes(node_context)
          nodes = node_context.instance_variable_get(:@nesting_nodes)
          return nil unless nodes.is_a?(Array)
          return nil unless nodes.first.is_a?(Prism::ProgramNode)

          nodes
        rescue
          nil
        end

        def initialize(node_context, log: nil)
          @log = log
          @nesting_nodes = self.class.nesting_nodes(node_context)
          @local_scopes = build_local_scopes
          @class_scope = @nesting_nodes&.reverse_each&.find { |node| CLASS_SCOPES.any? { |klass| node.is_a?(klass) } }
          @assignment_tables = {}.compare_by_identity
          @ivar_assignments = nil
        end

        attr_reader :class_scope

        def available?
          !@nesting_nodes.nil?
        end

        # The innermost local scope. Kept for introspection; assignment lookup uses every enclosing scope a block
        # or lambda can see.
        def local_scope
          @local_scopes.first
        end

        # RHS nodes of assignments to `name` that happen before `before_offset`, from the innermost enclosing scope
        # outward through the scopes a closure can read (FR-M2-05). Operator assignments have no standalone RHS and
        # are skipped.
        def assignment_value_nodes(name, before_offset)
          @local_scopes.flat_map do |scope|
            table = @assignment_tables[scope] ||= collect(scope, excluded: NESTED_LOCAL_SCOPES)
            next [] unless table

            (table[name.to_s] || [])
              .select { |offset, _value| offset < before_offset }
              .sort_by(&:first)
              .map(&:last)
          end
        end

        # RHS nodes of assignments to the instance variable `name` anywhere in the enclosing class or module
        # (FR-M2-08), including method bodies but not nested classes.
        def ivar_value_nodes(name)
          table = ivar_assignments
          return [] unless table

          (table[name.to_s] || []).sort_by(&:first).map(&:last)
        end

        # Simple block parameters as `[name, kind]` pairs. Destructured parameters are skipped.
        def block_parameters
          block = @nesting_nodes&.reverse_each&.find { |node| node.is_a?(Prism::BlockNode) }
          return [] unless block

          parameters = block.parameters
          return [] unless parameters.is_a?(Prism::BlockParametersNode)

          list = parameters.parameters
          return [] unless list.is_a?(Prism::ParametersNode)

          result = []
          list.requireds.each { |parameter| append_parameter(result, parameter, :required) }
          list.optionals.each { |parameter| append_parameter(result, parameter, :optional) }
          append_parameter(result, list.rest, :rest)
          list.keywords.each { |parameter| append_parameter(result, parameter, :keyword) }
          append_parameter(result, list.keyword_rest, :keyword_rest)
          append_parameter(result, list.block, :block)
          result
        end

        private

        def append_parameter(result, parameter, kind)
          return unless parameter.respond_to?(:name) && parameter.name

          result << [parameter.name.to_s, kind]
        end

        # Innermost first. Lambdas can read the locals of the scopes that enclose them, so the walk continues past
        # them; defs and class bodies cannot, so the walk stops there.
        def build_local_scopes
          boundaries = Array(@nesting_nodes).select do |node|
            LOCAL_SCOPE_BOUNDARIES.any? { |klass| node.is_a?(klass) }
          end

          scopes = []
          boundaries.reverse_each do |node|
            scopes << node
            break unless node.is_a?(Prism::LambdaNode)
          end
          scopes
        end

        def ivar_assignments
          @ivar_assignments ||= begin
            scope = @class_scope
            scope ? collect(scope, excluded: CLASS_SCOPES) : nil
          end
        end

        # Walks `root` collecting assignment RHS nodes. Children that open a new scope are not descended into,
        # except the root itself.
        def collect(root, excluded:)
          table = Hash.new { |hash, key| hash[key] = [] }
          stack = [root]

          until stack.empty?
            current = stack.pop

            case current
            when Prism::LocalVariableWriteNode
              table[current.name.to_s] << [current.location.start_offset, current.value]
            when Prism::LocalVariableAndWriteNode, Prism::LocalVariableOrWriteNode
              table[current.name.to_s] << [current.location.start_offset, current.value]
            when Prism::InstanceVariableWriteNode
              table[current.name.to_s] << [current.location.start_offset, current.value]
            when Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableOrWriteNode
              table[current.name.to_s] << [current.location.start_offset, current.value]
            end

            current.compact_child_nodes.each do |child|
              next if !child.equal?(root) && excluded.any? { |klass| child.is_a?(klass) }

              stack << child
            end
          end

          table
        rescue => e
          @log&.warn("Scope walk failed: #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
