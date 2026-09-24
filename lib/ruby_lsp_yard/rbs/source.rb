# frozen_string_literal: true

require "rbs"

require_relative "../signature"
require_relative "converter"

module RubyLsp
  module Yard
    module Rbs
      # Answers `(owner, name, singleton)` signature lookups from the RBS environment (FR-M3-01..04): parameters,
      # returns, overloads, block signatures and the type variables the inference engine substitutes. Only owners
      # that exist in the RBS environment (core and stdlib) are served, so workspace classes keep their YARD
      # definitions. Never raises: failures degrade to nil (NFR-R1).
      class Source
        def initialize(loader, log: nil)
          @loader = loader
          @log = log
          @definitions = {}
          @mutex = Mutex.new
        end

        def ready?
          @loader.ready?
        end

        # Notifies the block when the environment becomes ready (or immediately when it already is).
        def subscribe(&block)
          @loader.subscribe(&block)
        end

        def lookup(owner, name, singleton: false)
          return nil unless ready?

          method_name = name.to_s
          return nil if method_name.empty?

          base, singleton = normalize_owner(owner, singleton)
          return nil if base.empty?

          type_name = type_name_for(base)
          return nil unless type_name

          definition = definition_for(type_name, singleton)
          return nil unless definition

          method = definition.methods[method_name.to_sym]
          return nil unless method

          build_signature(base, method_name, singleton, definition, method)
        rescue => e
          @log&.error("RBS lookup failed for #{owner}##{name}: #{e.class}: #{e.message}")
          nil
        end

        private

        def converter
          @converter ||= Converter.new(environment: @loader.environment, builder: @loader.builder)
        end

        def definition_for(type_name, singleton)
          key = [type_name.to_s, singleton]
          @mutex.synchronize { return @definitions[key] if @definitions.key?(key) }

          builder = @loader.builder
          return nil unless builder

          definition = singleton ? builder.build_singleton(type_name) : builder.build_instance(type_name)
          @mutex.synchronize { @definitions[key] = definition }
          definition
        end

        def build_signature(base, name, singleton, definition, method)
          method_types = method.method_types
          primary = method_types.first
          return nil unless primary

          # The block signature can live on a later overload (`Hash#each` lists the enumerator form first), so
          # block parameter types come from the first overload that takes a block.
          block_type = method_types.find(&:block)
          yield_params, yield_returns = block_type ? yield_info(block_type) : [[], []]
          overloads = (method_types.size > 1) ? method_types.map { |mt| overload_signature(name, mt) } : []

          Signature.new(
            owner: base,
            name: name,
            singleton: singleton,
            visibility: method.accessibility,
            params: params_from_function(primary.type),
            return_types: return_type_of(primary.type),
            overloads: overloads,
            yield_params: yield_params,
            yield_returns: yield_returns,
            type_params: definition.type_params.map { |param| param.name.to_sym },
            method_type_params: method_type_params(primary),
            documented: true,
            source: :rbs
          )
        end

        def overload_signature(name, method_type)
          yield_params, yield_returns = yield_info(method_type)
          Signature.new(
            name: name,
            params: params_from_function(method_type.type),
            return_types: return_type_of(method_type.type),
            yield_params: yield_params,
            yield_returns: yield_returns,
            method_type_params: method_type_params(method_type),
            documented: true,
            source: :rbs
          )
        end

        # Methods declared with `...` or an untyped function carry no typed parameters or return.
        def return_type_of(function)
          function.respond_to?(:return_type) ? converter.convert(function.return_type) : Types::UNKNOWN
        end

        def params_from_function(function)
          return [] unless function.respond_to?(:required_positionals)

          params = []
          index = 0

          function.required_positionals.each do |param|
            params << positional_param(param, :required, index)
            index += 1
          end
          function.optional_positionals.each do |param|
            params << positional_param(param, :optional, index)
            index += 1
          end
          if (rest = function.rest_positionals)
            params << Signature::Param.new(name: rest.name || :"arg#{index}", kind: :rest, types: converter.convert(rest.type))
            index += 1
          end
          function.trailing_positionals.each do |param|
            params << positional_param(param, :required, index)
            index += 1
          end
          function.required_keywords.each do |keyword, param|
            params << Signature::Param.new(name: keyword, kind: :keyword, types: converter.convert(param.type))
          end
          function.optional_keywords.each do |keyword, param|
            params << Signature::Param.new(name: keyword, kind: :keyword_optional, types: converter.convert(param.type))
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

        def positional_param(param, kind, index)
          Signature::Param.new(name: param.name || :"arg#{index}", kind: kind, types: converter.convert(param.type))
        end

        def yield_info(method_type)
          block = method_type.block
          return [[], []] unless block

          function = block.type
          [params_from_function(function), [converter.convert(function.return_type)]]
        end

        def method_type_params(method_type)
          return [] unless method_type.respond_to?(:type_param_names)

          method_type.type_param_names.map(&:to_sym)
        end

        def normalize_owner(owner, singleton)
          base = owner.to_s
          if base.include?("::<Class:")
            base = base.sub(/::<Class:[^>]+>\z/, "")
            singleton = true
          end
          [base.delete_prefix("::"), singleton]
        end

        def type_name_for(base)
          type_name = ::RBS::TypeName.parse("::#{base}")
          environment = @loader.environment
          return nil unless environment&.class_decls&.key?(type_name)

          type_name
        rescue ::RBS::ParsingError
          nil
        end
      end
    end
  end
end
