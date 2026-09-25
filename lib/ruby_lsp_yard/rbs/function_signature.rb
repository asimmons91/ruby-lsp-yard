# frozen_string_literal: true

require "rbs"

require_relative "../signature"

module RubyLsp
  module Yard
    module Rbs
      # Shared RBS function-to-parameter conversion used by the core/stdlib source and the rbs-inline source
      # (FR-M3-01, FR-M7-04). Never raises: unrepresentable pieces degrade to empty lists (NFR-R1).
      module FunctionSignature
        module_function

        # The positional, keyword and rest parameters of an `RBS::Types::Function`.
        def params_from_function(function, converter)
          return [] unless function.respond_to?(:required_positionals)

          params = []
          index = 0

          function.required_positionals.each do |param|
            params << positional_param(param, :required, index, converter)
            index += 1
          end
          function.optional_positionals.each do |param|
            params << positional_param(param, :optional, index, converter)
            index += 1
          end
          if (rest = function.rest_positionals)
            params << Signature::Param.new(
              name: rest.name || :"arg#{index}",
              kind: :rest,
              types: converter.convert(rest.type)
            )
            index += 1
          end
          function.trailing_positionals.each do |param|
            params << positional_param(param, :required, index, converter)
            index += 1
          end
          function.required_keywords.each do |keyword, param|
            params << Signature::Param.new(name: keyword, kind: :keyword, types: converter.convert(param.type))
          end
          function.optional_keywords.each do |keyword, param|
            params << Signature::Param.new(
              name: keyword,
              kind: :keyword_optional,
              types: converter.convert(param.type)
            )
          end
          if (rest = function.rest_keywords)
            params << Signature::Param.new(
              name: rest.name || :keyword_rest,
              kind: :keyword_rest,
              types: converter.convert(rest.type)
            )
          end

          params
        end

        def positional_param(param, kind, index, converter)
          Signature::Param.new(name: param.name || :"arg#{index}", kind: kind, types: converter.convert(param.type))
        end

        # The block parameter types and return type of a method type.
        def yield_info(method_type, converter)
          block = method_type.block
          return [[], []] unless block

          function = block.type
          [params_from_function(function, converter), [converter.convert(function.return_type)]]
        end

        def method_type_params(method_type)
          return [] unless method_type.respond_to?(:type_param_names)

          method_type.type_param_names.map(&:to_sym)
        end
      end
    end
  end
end
