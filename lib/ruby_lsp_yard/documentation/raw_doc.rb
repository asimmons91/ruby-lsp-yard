# frozen_string_literal: true

module RubyLsp
  module Yard
    module Documentation
      # Raw view of a parsed docstring, before type strings are turned into the type model. All fields are optional
      # and never raise on malformed input (NFR-R1).
      class RawDoc
        attr_accessor :summary, :deprecated, :reference
        attr_reader :params, :returns, :yields, :yield_params, :yield_returns, :options, :raises, :metadata,
          :directives, :overloads

        def initialize(
          summary: "",
          params: [],
          returns: [],
          yields: [],
          yield_params: [],
          yield_returns: [],
          options: [],
          raises: [],
          deprecated: nil,
          overloads: [],
          metadata: [],
          directives: [],
          reference: nil
        )
          @summary = summary
          @params = params
          @returns = returns
          @yields = yields
          @yield_params = yield_params
          @yield_returns = yield_returns
          @options = options
          @raises = raises
          @deprecated = deprecated
          @overloads = overloads
          @metadata = metadata
          @directives = directives
          @reference = reference
        end

        def deprecated?
          !@deprecated.nil?
        end

        def return_types
          @returns.flat_map(&:types)
        end

        # Whether any tag (as opposed to a directive) carried information. A leading `(see ...)` reference alone
        # does not count: when it cannot be resolved the signature should fall back to its ancestors.
        def tagged?
          !(params.empty? && returns.empty? && yields.empty? && yield_params.empty? &&
            yield_returns.empty? && options.empty? && raises.empty? && overloads.empty? &&
            metadata.empty? && !deprecated?)
        end

        def empty?
          summary.to_s.empty? && !tagged? && directives.empty?
        end
      end

      RawParam = Struct.new(:name, :types, :text)
      RawReturn = Struct.new(:types, :text)
      RawYield = Struct.new(:names, :text)
      RawOption = Struct.new(:name, :key, :types, :default, :text)
      RawRaise = Struct.new(:types, :text)
      RawMetadata = Struct.new(:tag, :name, :types, :text)
      RawOverload = Struct.new(:signature, :doc)

      # A single `@!method`, `@!attribute`, `@!parse`, `@!visibility`, `@!macro` or `@!domain` directive. `doc` holds
      # the nested docstring for method and attribute directives; `text` holds the raw code for `@!parse`, the new
      # visibility for `@!visibility`, or the macro data for `@!macro`; `types` carries the macro flags (`attach`,
      # `new`) or the domain type expressions.
      RawDirective = Struct.new(:kind, :name, :singleton, :types, :text, :doc)
    end
  end
end
