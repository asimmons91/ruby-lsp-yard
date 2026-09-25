# frozen_string_literal: true

require "prism"

require_relative "../indexer/definition"
require_relative "../signature"
require_relative "../types"

module RubyLsp
  module Yard
    module Documentation
      # Builds {Signature} objects from parsed docstrings (FR-M1-01..10). Used by the signature store for indexed
      # definitions and directives, and by the macro processor for definitions expanded from `@!macro` text. Type
      # expressions are parsed against the owner's lexical nesting. Never raises: failures degrade to nil (NFR-R1).
      class SignatureBuilder
        def initialize(adapter, log: nil)
          @adapter = adapter
          @log = log
          @parsers = {}
        end

        # Builds the signature of an indexed definition from its raw docstring. `visibility` overrides the
        # definition's own visibility (`@!visibility`).
        def build(definition, raw, name:, singleton:, visibility: nil)
          owner = definition.owner || ""
          parser = parser_for(owner)
          params, unmatched = match_params(definition.parameters, raw.params, parser)

          Signature.new(
            owner: owner,
            name: name,
            singleton: singleton_for(definition) || singleton,
            kind: (definition.kind == :attribute) ? :attribute : :method,
            visibility: visibility || definition.visibility,
            uri: definition.uri,
            location: definition.location,
            summary: raw.summary,
            params: params,
            return_types: parser.parse_list(raw.return_types),
            overloads: build_overloads(raw.overloads, name, parser),
            raises: build_raises(raw.raises, parser),
            deprecated: raw.deprecated,
            metadata: raw.metadata,
            yields: raw.yields,
            yield_params: params_from_raw(raw.yield_params, parser),
            yield_returns: raw.yield_returns.map { |raw_return| parser.parse_list(raw_return.types) },
            options: build_options(raw.options, parser),
            unmatched_params: unmatched,
            documented: raw.tagged?
          )
        end

        # Builds a signature for a method defined inside `@!method`/`@!parse` text or a macro expansion.
        def from_prism(owner:, raw:, name:, singleton:, parameters:, visibility: nil, uri: nil, location: nil,
          kind: :method)
          parser = parser_for(owner)
          params, unmatched = match_params(parameters, raw.params, parser)

          Signature.new(
            owner: owner,
            name: name,
            singleton: singleton,
            kind: kind,
            visibility: visibility || :public,
            uri: uri,
            location: location,
            params: params,
            unmatched_params: unmatched,
            return_types: parser.parse_list(raw.return_types),
            raises: build_raises(raw.raises, parser),
            deprecated: raw.deprecated,
            metadata: raw.metadata,
            summary: raw.summary,
            documented: true
          )
        end

        # Builds a signature for an `@!method` directive or a macro expansion's method directive.
        def from_directive(owner:, name:, singleton:, doc:, visibility: nil, kind: :method, uri: nil, location: nil)
          parser = parser_for(owner)

          Signature.new(
            owner: owner,
            name: name,
            singleton: singleton,
            kind: kind,
            visibility: visibility || :public,
            uri: uri,
            location: location,
            params: params_from_raw(doc.params, parser),
            return_types: parser.parse_list(doc.return_types),
            raises: build_raises(doc.raises, parser),
            deprecated: doc.deprecated,
            metadata: doc.metadata,
            yields: doc.yields,
            yield_params: params_from_raw(doc.yield_params, parser),
            yield_returns: doc.yield_returns.map { |raw_return| parser.parse_list(raw_return.types) },
            options: build_options(doc.options, parser),
            summary: doc.summary,
            documented: true
          )
        end

        # Interprets `@!method`, `@!attribute` and `@!parse` directives from `raw` into `entries` keyed by
        # `[name, singleton]`. `uri`/`location` point at the source the directives came from (the DSL call site for
        # macros). Only these three directives create definitions (FR-M7-01).
        def apply_directives(entries, owner:, raw:, visibility: nil, uri: nil, location: nil)
          raw.directives.each do |directive|
            case directive.kind
            when :method
              add_method_directive(entries, owner, raw, directive, visibility, uri, location)
            when :attribute
              add_attribute_directive(entries, owner, directive, visibility, uri, location)
            when :parse
              add_parse_entries(entries, owner, raw, directive, visibility, uri, location)
            end
          end
          entries
        end

        def extract_visibility(raw)
          raw.directives.reverse_each do |directive|
            return directive.text.to_s.to_sym if directive.kind == :visibility
          end
          nil
        end

        def parser_for(owner)
          @parsers[owner] ||= Types::Parser.new(
            resolver: ->(name, nesting) { @adapter.resolve_constant(name, nesting) },
            nesting: nesting_for(owner)
          )
        end

        # Constant lookup nesting for an owner: `FixtureProject::Animal` -> `["FixtureProject", "Animal"]`.
        def nesting_for(owner)
          base_owner(owner).split("::").reject(&:empty?)
        end

        def base_owner(name)
          name.to_s.sub(/::<Class:[^>]+>\z/, "")
        end

        def receiver_owner(owner, singleton)
          return owner.to_s unless singleton

          unqualified = owner.to_s.split("::").last
          "#{owner}::<Class:#{unqualified}>"
        end

        def singleton_for(definition)
          definition.owner.to_s.include?("::<Class:")
        end

        def match_params(definition_params, raw_params, parser)
          remaining = raw_params.dup

          params = definition_params.map do |parameter|
            tag = remaining.find { |raw| normalize_name(raw.name) == normalize_name(parameter.name) }
            remaining.delete(tag) if tag

            Signature::Param.new(
              name: parameter.name,
              kind: parameter.kind,
              types: tag ? parser.parse_list(tag.types) : Types::UNKNOWN,
              description: tag&.text
            )
          end

          [params, remaining]
        end

        def params_from_raw(raw_params, parser)
          raw_params.filter_map do |raw|
            next if raw.name.to_s.empty?

            Signature::Param.new(
              name: normalize_name(raw.name).to_sym,
              kind: :required,
              types: parser.parse_list(raw.types),
              description: raw.text
            )
          end
        end

        def normalize_name(name)
          name.to_s.sub(/\A[*&]+/, "").sub(/:+\z/, "")
        end

        def build_overloads(raw_overloads, name, parser)
          raw_overloads.map do |overload|
            raw = overload.doc
            Signature.new(
              name: name,
              params: params_from_raw(raw.params, parser),
              return_types: parser.parse_list(raw.return_types),
              signature_text: overload.signature,
              summary: raw.summary,
              yields: raw.yields,
              yield_params: params_from_raw(raw.yield_params, parser),
              yield_returns: raw.yield_returns.map { |raw_return| parser.parse_list(raw_return.types) },
              raises: build_raises(raw.raises, parser),
              deprecated: raw.deprecated,
              documented: true
            )
          end
        end

        def build_raises(raw_raises, parser)
          raw_raises.map { |raw| [parser.parse_list(raw.types), raw.text] }
        end

        def build_options(raw_options, parser)
          raw_options.map do |raw|
            Signature::Option.new(
              name: raw.name,
              key: raw.key,
              types: parser.parse_list(raw.types),
              default: raw.default,
              description: raw.text
            )
          end
        end

        private

        def add_method_directive(entries, owner, raw, directive, visibility, uri, location)
          return if directive.name.to_s.empty?

          entries[[directive.name.to_s, directive.singleton]] ||= from_directive(
            owner: owner,
            name: directive.name.to_s,
            singleton: directive.singleton,
            doc: directive.doc,
            visibility: visibility,
            kind: :method,
            uri: uri,
            location: location
          )
        end

        def add_attribute_directive(entries, owner, directive, visibility, uri, location)
          name = directive.name.to_s
          return if name.empty?

          types = if directive.doc.return_types.any?
            parser_for(owner).parse_list(directive.doc.return_types)
          else
            Types::UNKNOWN
          end
          readable, writable = attribute_accessors(directive.types)

          if readable
            entries[[name, false]] ||= Signature.new(
              owner: owner,
              name: name,
              kind: :attribute,
              visibility: visibility || :public,
              uri: uri,
              location: location,
              return_types: types,
              summary: directive.doc.summary,
              documented: true
            )
          end

          if writable
            entries[["#{name}=", false]] ||= Signature.new(
              owner: owner,
              name: "#{name}=",
              kind: :attribute,
              visibility: visibility || :public,
              uri: uri,
              location: location,
              params: [Signature::Param.new(name: :value, kind: :required, types: types)],
              documented: true
            )
          end
        end

        def attribute_accessors(types)
          return [true, true] if types.empty?

          joined = types.join
          [joined.include?("r"), joined.include?("w")]
        end

        def add_parse_entries(entries, owner, raw, directive, visibility, uri, location)
          result = Prism.parse(directive.text.to_s)
          return unless result.success?

          result.value.statements.body.each do |node|
            case node
            when Prism::DefNode
              add_prism_method(entries, owner, raw, node, visibility, uri, location)
            when Prism::CallNode
              add_prism_attribute(entries, owner, raw, node, visibility, uri, location)
            end
          end
        end

        def add_prism_method(entries, owner, raw, node, visibility, uri, location)
          name = node.name.to_s
          singleton = node.receiver.is_a?(Prism::SelfNode)
          entries[[name, singleton]] ||= from_prism(
            owner: owner,
            raw: raw,
            name: name,
            singleton: singleton,
            parameters: prism_parameters(node.parameters),
            visibility: visibility,
            uri: uri,
            location: location || prism_location(node)
          )
        end

        def add_prism_attribute(entries, owner, raw, node, visibility, uri, location)
          return unless node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)

          readable, writable = case node.name
          when :attr_reader then [true, false]
          when :attr_writer then [false, true]
          when :attr_accessor, :attr then [true, true]
          else return
          end

          names = Array(node.arguments&.arguments).filter_map do |argument|
            argument.value.to_s if argument.is_a?(Prism::SymbolNode)
          end
          types = parser_for(owner).parse_list(raw.return_types)

          names.each do |name|
            if readable
              entries[[name, false]] ||= Signature.new(
                owner: owner,
                name: name,
                kind: :attribute,
                visibility: visibility || :public,
                uri: uri,
                location: location || prism_location(node),
                return_types: types,
                documented: true
              )
            end

            if writable
              entries[["#{name}=", false]] ||= Signature.new(
                owner: owner,
                name: "#{name}=",
                kind: :attribute,
                visibility: visibility || :public,
                uri: uri,
                location: location || prism_location(node),
                params: [Signature::Param.new(name: :value, kind: :required, types: types)],
                documented: true
              )
            end
          end
        end

        def prism_location(node)
          location = node.respond_to?(:name_loc) ? node.name_loc : nil
          location ||= node.message_loc if node.respond_to?(:message_loc)
          location ||= node.location
          return nil unless location

          Indexer::Location.new(
            start_line: location.start_line,
            start_column: location.start_column,
            end_line: location.end_line,
            end_column: location.end_column
          )
        end

        def prism_parameters(parameters)
          return [] unless parameters

          result = []
          parameters.requireds.each { |parameter| result << Indexer::Parameter.new(parameter.name, :required) }
          parameters.optionals.each { |parameter| result << Indexer::Parameter.new(parameter.name, :optional) }
          parameters.posts.each { |parameter| result << Indexer::Parameter.new(parameter.name, :required) }

          rest = parameters.rest
          result << Indexer::Parameter.new(rest.name, :rest) if rest.respond_to?(:name) && rest.name

          parameters.keywords.each do |parameter|
            kind = parameter.is_a?(Prism::OptionalKeywordParameterNode) ? :keyword_optional : :keyword
            result << Indexer::Parameter.new(parameter.name, kind)
          end

          keyword_rest = parameters.keyword_rest
          if keyword_rest.is_a?(Prism::KeywordRestParameterNode) && keyword_rest.name
            result << Indexer::Parameter.new(keyword_rest.name, :keyword_rest)
          end

          block = parameters.block
          result << Indexer::Parameter.new(block.name, :block) if block.respond_to?(:name) && block.name

          result
        end
      end
    end
  end
end
