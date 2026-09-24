# frozen_string_literal: true

require "prism"

require_relative "../type_walker"
require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/ReturnTypeMismatch (off by default): an explicit `return <literal>` conflicts with the method's YARD
        # `@return` type (FR-M5-01, light type checking). `return nil` is ignored because guard returns are
        # idiomatic, and overloaded or RBS-sourced methods are skipped.
        class ReturnTypeMismatch < Base
          class << self
            def key
              "YARD/ReturnTypeMismatch"
            end

            def default_severity
              :off
            end

            def check(target, context)
              return [] unless target.documented? && target.def_node?
              return [] unless target.raw_doc.returns.any?
              return [] if target.raw_doc.overloads.any?

              declared = context.parser(target).parse_list(target.raw_doc.return_types)
              return [] if declared.nil? || Types.unknown?(declared) || declared == Types::VOID || declared == Types::SELF

              diagnostics = []
              each_return(target.node) do |return_node|
                value = return_value(return_node)
                next unless value

                actual = literal_type(value)
                next unless actual && actual != Types::NIL_TYPE
                next if TypeWalker.compatible?(declared, actual, adapter: context.adapter)

                diagnostics << diagnostic(
                  "`return #{value.slice}` is #{Types::Formatter.format(actual)}, but " \
                    "`@return [#{Types::Formatter.format(declared)}]` is declared",
                  range: context.prism_range(value.location),
                  target: target
                )
              end
              diagnostics
            rescue => e
              context.log&.error("Return type check failed: #{e.class}: #{e.message}")
              []
            end

            private

            # `return` with exactly one literal argument. A bare `return` inherits the last expression and is not
            # checked; multiple return values are skipped as unsupported.
            def return_value(return_node)
              arguments = return_node.arguments&.arguments
              return nil unless arguments&.size == 1

              value = arguments.first
              return nil if value.is_a?(Prism::SplatNode)

              value
            end

            # Walks the method body. `return` inside `do ... end` blocks returns from the method so blocks are
            # included; lambdas and nested defs are not.
            def each_return(def_node)
              stack = [def_node.body]
              until stack.empty?
                node = stack.pop
                next unless node

                yield node if node.is_a?(Prism::ReturnNode)
                next if node.is_a?(Prism::LambdaNode) || node.is_a?(Prism::DefNode)

                node.compact_child_nodes.each { |child| stack << child }
              end
            end

            # The actual type of the return literal; complex expressions are left to the inference engine.
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
