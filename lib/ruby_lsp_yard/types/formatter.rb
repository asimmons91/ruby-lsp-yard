# frozen_string_literal: true

require_relative "model"

module RubyLsp
  module Yard
    module Types
      # Renders types back to YARD-ish type expressions for hover and signature help (D13). `Unknown` is rendered as
      # `untyped` as a last resort; feature code should omit unknown types instead of showing this text.
      module Formatter
        class << self
          def format(type)
            case type
            when Unknown then "untyped"
            when TypeVar then type.name.to_s
            when Special then format_special(type)
            when Ref then type.name
            when Instance then format_instance(type)
            when Singleton then format_singleton(type)
            when Union then format_union(type)
            when Tuple then "(#{type.types.map { |member| format(member) }.join(", ")})"
            when HashOf then "Hash{#{format(type.key)} => #{format(type.value)}}"
            when Duck then type.methods.map { |method| "##{method}" }.join(", ")
            when Literal then format_literal(type.value)
            else "untyped"
            end
          end

          private

          def format_special(type)
            (type.name == :boolean) ? "Boolean" : type.name.to_s
          end

          def format_instance(type)
            return type.name if type.type_args.empty?

            "#{type.name}<#{type.type_args.map { |argument| format(argument) }.join(", ")}>"
          end

          def format_singleton(type)
            return "Class<#{type.name}>" if type.type_args.empty?

            "Class<#{type.name}<#{type.type_args.map { |argument| format(argument) }.join(", ")}>>"
          end

          def format_union(type)
            non_nil = type.types.reject { |member| Types.nil_type?(member) }
            return "nil" if non_nil.empty?
            return "#{format(non_nil.first)}?" if non_nil.size == 1

            type.types.map { |member| format(member) }.join(" | ")
          end

          def format_literal(value)
            case value
            when Symbol then value.inspect
            when String then value.inspect
            else value.to_s
            end
          end
        end
      end
    end
  end
end
