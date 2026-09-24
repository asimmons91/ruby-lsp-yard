# frozen_string_literal: true

require "prism"

require_relative "documentation"
require_relative "indexer"
require_relative "signature"
require_relative "types"

module RubyLsp
  module Yard
    # Maps (owner, name, singleton) to a {Signature} built from YARD tags (FR-M1-10). Fills lazily and memoizes
    # (NFR-P5), follows `(see ...)` references and inheritance, interprets the M1 directives, and drops its caches
    # when watched files change (FR-M1-11). Never raises: failures degrade to `nil` (NFR-R1).
    class SignatureStore
      MISS = Object.new
      REFERENCE = /\A(?:(?<owner>[A-Za-z_][\w:]*))?(?<separator>[#.])(?<method>[^#.]+)\z/

      def initialize(adapter, log: nil, rbs: nil, gem_cache: nil)
        @adapter = adapter
        @log = log
        @rbs = rbs
        @gem_cache = gem_cache
        @extractor = Documentation::TagExtractor.new(log: log)
        @cache = {}
        @directive_cache = {}
        @visibility_overrides = {}
        @parsers = {}
        @mutex = Mutex.new

        adapter.subscribe { |uris| invalidate(uris) }
        # Core signatures looked up while the RBS environment was still loading were pinned to their YARD/host
        # fallback; drop the caches once RBS can answer (FR-M3-04).
        @rbs&.subscribe { invalidate(nil) }
      end

      def lookup(owner, name, singleton: false)
        return nil if owner.nil? || name.nil?

        key = [owner.to_s, name.to_s, singleton]
        cached = @mutex.synchronize { @cache.fetch(key, MISS) }
        return cached unless cached.equal?(MISS)

        signature = build(key[0], key[1], singleton, visited: [])
        @mutex.synchronize { @cache[key] = signature || MISS }
        signature
      rescue => e
        @log&.error("Signature lookup failed for #{owner}##{name}: #{e.class}: #{e.message}")
        nil
      end

      # A watched file changed. Entries are rebuilt lazily on the next lookup; clearing everything is a superset of
      # invalidating just the changed files and keeps the caches consistent.
      def invalidate(_uris)
        @mutex.synchronize do
          @cache.clear
          @directive_cache.clear
          @visibility_overrides.clear
          @parsers.clear
        end
      end

      private

      def build(owner, name, singleton, visited:)
        key = [owner, name, singleton]
        return nil if visited.include?(key)

        visited += [key]

        # FR-M3-04 (D5): where RBS and YARD both describe a method, RBS wins.
        rbs_signature = rbs_lookup(owner, name, singleton)
        return rbs_signature if rbs_signature

        # Populates visibility overrides stored on the owner's own definitions.
        directives = directive_entries(owner)
        fallback = nil

        @adapter.method_definitions(owner, name, singleton: singleton).each do |definition|
          signature = signature_from_definition(definition, name, singleton, visited)
          next unless signature
          return signature if signature.documented?

          fallback ||= signature
        end

        directive = directives[[name, singleton]]
        return directive if directive

        receiver = receiver_owner(owner, singleton)
        ancestors = @adapter.ancestors(receiver)

        ancestors.each do |ancestor|
          next if ancestor == receiver

          # Ancestors contribute their instance methods to both kinds of receivers (`extend` mixes a module's
          # instance methods into the singleton), so the singleton flag is not passed on.
          inherited_rbs = rbs_lookup(ancestor, name, false)
          return inherited_rbs if inherited_rbs

          @adapter.method_definitions(ancestor, name).each do |definition|
            signature = signature_from_definition(definition, name, singleton, visited)
            next unless signature
            return signature if signature.documented?

            fallback ||= signature
          end
        end

        # Directives attached to a superclass comment or method.
        ancestors.each do |ancestor|
          ancestor_owner = base_owner(ancestor)
          next if ancestor_owner == owner

          signature = directive_entries(ancestor_owner)[[name, singleton]]
          return signature if signature
        end

        fallback
      end

      def signature_from_definition(definition, name, singleton, visited)
        gem = gem_identity(definition)
        cache_key = gem_cache_key(definition, singleton)

        if gem && cache_key
          cached = @gem_cache&.read(gem, cache_key)
          return cached if cached
        end

        raw = @extractor.extract(definition.comments)

        if raw.reference
          resolved = resolve_reference(raw.reference, definition, visited)
          return resolved if resolved
        end

        signature = build_signature(definition, raw, name: name, singleton: singleton)
        @gem_cache&.write(gem, cache_key, signature) if gem && cache_key && signature&.documented?
        signature
      rescue => e
        @log&.error("Failed to build signature for #{definition.name}: #{e.class}: #{e.message}")
        nil
      end

      # FR-M3-05: gem docstrings are parsed lazily and the built signatures persist to the disk cache.
      def gem_identity(definition)
        return nil unless @gem_cache

        @gem_cache.identity(definition.uri || definition.file_name)
      rescue
        nil
      end

      def gem_cache_key(definition, singleton)
        return nil unless definition.owner && definition.name

        [definition.owner, definition.name, singleton_for(definition) || singleton]
      end

      # FR-M3-04: RBS answers for core and stdlib owners (and their ancestors) before YARD.
      def rbs_lookup(owner, name, singleton)
        @rbs&.lookup(owner, name, singleton: singleton)
      rescue => e
        @log&.error("RBS signature lookup failed for #{owner}##{name}: #{e.class}: #{e.message}")
        nil
      end

      def build_signature(definition, raw, name:, singleton:)
        owner = definition.owner || ""
        parser = parser_for(owner)
        params, unmatched = match_params(definition.parameters, raw.params, parser)

        Signature.new(
          owner: owner,
          name: name,
          singleton: singleton_for(definition) || singleton,
          kind: (definition.kind == :attribute) ? :attribute : :method,
          visibility: visibility_for(definition, singleton) || definition.visibility,
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

      # --- Directives (FR-M1-03) ---------------------------------------------------------------------------------

      def directive_entries(owner)
        @mutex.synchronize { return @directive_cache[owner] if @directive_cache.key?(owner) }

        entries = build_directive_entries(owner)
        @mutex.synchronize { @directive_cache[owner] = entries }
        entries
      end

      def build_directive_entries(owner)
        entries = {}
        own_owners = [owner, receiver_owner(owner, true)]

        definitions = []
        definitions.concat(@adapter.methods_of(owner))
        definitions.concat(@adapter.methods_of(owner, singleton: true))
        definitions.concat(@adapter.constant_definitions(owner))

        definitions.each do |definition|
          next unless definition.owner.nil? || own_owners.include?(definition.owner)
          next unless definition.comments.include?("@!")

          raw = @extractor.extract(definition.comments)
          visibility = extract_visibility(raw)
          apply_visibility_override(definition, visibility) if visibility

          raw.directives.each do |directive|
            case directive.kind
            when :method
              add_method_directive(entries, owner, raw, directive, visibility)
            when :attribute
              add_attribute_directive(entries, owner, directive, visibility)
            when :parse
              add_parse_entries(entries, owner, raw, directive, visibility)
            end
          end
        end

        entries
      end

      def add_method_directive(entries, owner, raw, directive, visibility)
        return if directive.name.to_s.empty?

        entries[[directive.name.to_s, directive.singleton]] ||= directive_signature(
          owner: owner,
          name: directive.name.to_s,
          singleton: directive.singleton,
          doc: directive.doc,
          visibility: visibility,
          kind: :method
        )
      end

      def add_attribute_directive(entries, owner, directive, visibility)
        name = directive.name.to_s
        return if name.empty?

        types = directive.doc.return_types.any? ? parser_for(owner).parse_list(directive.doc.return_types) : Types::UNKNOWN
        readable, writable = attribute_accessors(directive.types)

        if readable
          entries[[name, false]] ||= Signature.new(
            owner: owner,
            name: name,
            kind: :attribute,
            visibility: visibility || :public,
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

      def add_parse_entries(entries, owner, raw, directive, visibility)
        result = Prism.parse(directive.text.to_s)
        return unless result.success?

        result.value.statements.body.each do |node|
          case node
          when Prism::DefNode
            add_prism_method(entries, owner, raw, node, visibility)
          when Prism::CallNode
            add_prism_attribute(entries, owner, raw, node, visibility)
          end
        end
      end

      def add_prism_method(entries, owner, raw, node, visibility)
        name = node.name.to_s
        singleton = node.receiver.is_a?(Prism::SelfNode)
        entries[[name, singleton]] ||= prism_signature(
          owner: owner,
          raw: raw,
          name: name,
          singleton: singleton,
          parameters: prism_parameters(node.parameters),
          visibility: visibility
        )
      end

      def add_prism_attribute(entries, owner, raw, node, visibility)
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
              params: [Signature::Param.new(name: :value, kind: :required, types: types)],
              documented: true
            )
          end
        end
      end

      def prism_signature(owner:, raw:, name:, singleton:, parameters:, visibility:)
        parser = parser_for(owner)
        params, unmatched = match_params(parameters, raw.params, parser)

        Signature.new(
          owner: owner,
          name: name,
          singleton: singleton,
          visibility: visibility || :public,
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

      def directive_signature(owner:, name:, singleton:, doc:, visibility:, kind:)
        parser = parser_for(owner)

        Signature.new(
          owner: owner,
          name: name,
          singleton: singleton,
          kind: kind,
          visibility: visibility || :public,
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

      # --- Helpers -----------------------------------------------------------------------------------------------

      def resolve_reference(reference, definition, visited)
        match = REFERENCE.match(reference.to_s)
        return nil unless match

        owner = if match[:owner]
          @adapter.resolve_constant(match[:owner], nesting_for(definition.owner.to_s))
        else
          base_owner(definition.owner.to_s)
        end
        return nil if owner.nil? || owner.empty?

        singleton = match[:separator] == "."
        key = [owner, match[:method], singleton]
        return nil if visited.include?(key)

        build(owner, match[:method], singleton, visited: visited)
      end

      def visibility_for(definition, singleton)
        # `@!visibility` overrides are collected while scanning an owner's directives. A definition may belong to
        # an ancestor (inherited method), so make sure that owner has been scanned before reading the override.
        directive_entries(base_owner(definition.owner)) if definition.owner
        @visibility_overrides[[definition.owner, definition.name, singleton_for(definition) || singleton]]
      end

      def apply_visibility_override(definition, visibility)
        return if definition.owner.nil?

        @visibility_overrides[[definition.owner, definition.name, singleton_for(definition)]] = visibility
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
    end
  end
end
