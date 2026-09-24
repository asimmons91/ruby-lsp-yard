# frozen_string_literal: true

require "prism"

require_relative "../type_walker"
require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/ArgumentTypeMismatch (off by default): a literal argument's type conflicts with the `@param` type of a
        # method documented with YARD (FR-M5-01, light type checking). RBS-sourced signatures are skipped, as are
        # unions, duck types and type variables, so the rule stays conservative.
        class ArgumentTypeMismatch < Base
          NESTING_NODES = [
            Prism::ProgramNode,
            Prism::ClassNode,
            Prism::ModuleNode,
            Prism::SingletonClassNode,
            Prism::DefNode,
            Prism::BlockNode,
            Prism::LambdaNode
          ].freeze

          class << self
            def key
              "YARD/ArgumentTypeMismatch"
            end

            def default_severity
              :off
            end

            def document_rule?
              true
            end

            def check_document(context)
              return [] unless context.inference && context.store

              targets_by_node = context.targets.to_h { |target| [target.node.object_id, target] }
              diagnostics = []
              each_call(context.document.ast, nil, [], nil, targets_by_node, nil) do |node, node_context, target|
                break unless context.budget.check!

                diagnostics.concat(check_call(node, node_context, target, context))
              end
              diagnostics
            end

            private

            def each_call(node, parent, nesting_nodes, enclosing_call, targets_by_node, current_target, &block)
              current_target = targets_by_node[node.object_id] || current_target
              if node.is_a?(Prism::CallNode)
                node_context = RubyLsp::NodeContext.new(node, parent, nesting_nodes, enclosing_call)
                block.call(node, node_context, current_target)
              end

              child_nesting = (NESTING_NODES.any? { |klass| node.is_a?(klass) }) ? nesting_nodes + [node] : nesting_nodes
              child_call = node.is_a?(Prism::CallNode) ? node : enclosing_call
              node.compact_child_nodes.each do |child|
                each_call(child, node, child_nesting, child_call, targets_by_node, current_target, &block)
              end
            end

            def check_call(node, node_context, target, context)
              message = node.message.to_s
              return [] if message.empty?

              resolution = context.inference.resolution_for(node_context)
              return [] unless resolution && resolution.duck_methods.empty? && resolution.members.size == 1

              member = resolution.members.first
              signature = context.store.lookup(member.owner, message, singleton: member.singleton)
              return [] unless signature&.yard? && signature.documented?
              return [] if signature.overloads.any?

              arguments = Array(node.arguments&.arguments)
              return [] if arguments.empty?

              diagnostics = []
              positional = signature.params.select { |param| %i[required optional rest].include?(param.kind) }
              fixed, rest = positional.partition { |param| param.kind != :rest }
              rest = rest.first
              index = 0
              arguments.each do |argument|
                case argument
                when Prism::SplatNode, Prism::BlockArgumentNode
                  index += 1
                when Prism::KeywordHashNode
                  diagnostics.concat(keyword_diagnostics(argument, signature, target, context))
                else
                  diagnostics.concat(argument_diagnostics_for(argument, fixed, rest, index, target, context))
                  index += 1
                end
              end
              diagnostics
            rescue => e
              context.log&.error("Argument type check failed: #{e.class}: #{e.message}")
              []
            end

            # Fixed parameters are checked directly. Arguments beyond them belong to `*rest`, whose declared type is
            # the container (`Array<String>`), so only the element type is compared (FR-M5-01).
            def argument_diagnostics_for(node, fixed, rest, index, target, context)
              if index < fixed.size
                return argument_diagnostics(node, fixed[index], target, context)
              end
              return [] unless rest

              declared = rest_element_types(rest.types, index - fixed.size)
              return [] unless declared

              argument_diagnostics(node, rest, target, context, declared: declared)
            end

            def argument_diagnostics(node, param, target, context, declared: nil)
              return [] unless param

              declared ||= param.types
              return [] if declared.nil? || Types.unknown?(declared)

              actual = literal_type(node)
              return [] unless actual
              return [] if TypeWalker.compatible?(declared, actual, adapter: context.adapter)

              [diagnostic(
                message(node, actual, param_label(param), target&.name),
                range: context.prism_range(node.location),
                target: target
              )]
            end

            # `*rest` carries a container type in the signature; the argument should match its element. A bare
            # `Array`/`Enumerable` carries no element information, so nothing is reported. A non-container type is
            # treated as the element type, matching the loose YARD style `@param args [String]`.
            def rest_element_types(types, offset)
              case types
              when Types::Tuple
                types.types[offset]
              when Types::Instance
                if %w[Array Enumerable].include?(types.name)
                  (types.type_args.size == 1) ? types.type_args.first : nil
                else
                  types
                end
              when Types::Union, Types::TypeVar, Types::Duck, Types::HashOf
                nil
              else
                types
              end
            end

            def keyword_diagnostics(keyword_hash, signature, target, context)
              keywords = signature.params.select { |param| %i[keyword keyword_optional].include?(param.kind) }
              options = option_types(signature)

              Array(keyword_hash.elements).filter_map do |element|
                next unless element.is_a?(Prism::AssocNode)

                key = element.key
                next unless key.is_a?(Prism::SymbolNode)

                param = keywords.find { |candidate| normalize_name(candidate.name) == key.unescaped }
                declared, label = if param&.typed?
                  [param.types, param_label(param)]
                elsif options.key?(key.unescaped)
                  option = options[key.unescaped]
                  [option.types, "@option #{option.name} :#{key.unescaped} [#{Types::Formatter.format(option.types)}]"]
                end
                next if declared.nil? || Types.unknown?(declared)

                actual = literal_type(element.value)
                next unless actual
                next if TypeWalker.compatible?(declared, actual, adapter: context.adapter)

                diagnostic(
                  message(element.value, actual, label, target&.name),
                  range: context.prism_range(element.value.location),
                  target: target
                )
              end
            end

            # `@option options :key [Types]` documents the keys of a `**options` hash. YARD stores the pair name as
            # `":key"`, so the leading colon is stripped to match the keyword syntax.
            def option_types(signature)
              Array(signature.options).each_with_object({}) do |option, result|
                key = option.key.to_s.delete_prefix(":")
                result[key] = option unless key.empty?
              end
            end

            def param_label(param)
              "@param #{param.name} [#{Types::Formatter.format(param.types)}]"
            end

            def message(node, actual, label, method_name)
              "`#{node.slice}` is #{Types::Formatter.format(actual)}, but `#{label}`" \
                "#{" of `#{method_name}`" if method_name}"
            end

            # The actual type of the literal nodes the rule checks. Anything more complex is left to the inference
            # engine and skipped here.
            def literal_type(node)
              case node
              when Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode
                Types::Instance.new("String")
              when Prism::SymbolNode, Prism::InterpolatedSymbolNode
                Types::Instance.new("Symbol")
              when Prism::IntegerNode
                Types::Instance.new("Integer")
              when Prism::FloatNode
                Types::Instance.new("Float")
              when Prism::RationalNode
                Types::Instance.new("Rational")
              when Prism::ImaginaryNode
                Types::Instance.new("Complex")
              when Prism::TrueNode, Prism::FalseNode
                Types::BOOLEAN
              when Prism::NilNode
                Types::NIL_TYPE
              when Prism::ArrayNode
                Types::Instance.new("Array")
              when Prism::HashNode, Prism::KeywordHashNode
                Types::Instance.new("Hash")
              when Prism::RangeNode
                Types::Instance.new("Range")
              when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
                Types::Instance.new("Regexp")
              end
            end
          end
        end
      end
    end
  end
end
