# frozen_string_literal: true

require "rubydex"

require_relative "adapter"
require_relative "definition"

module RubyLsp
  module Yard
    module Indexer
      # Indexer Adapter for Ruby LSP 0.27+, backed by `Rubydex` (FR-M6-01).
      #
      # Rubydex represents a few things differently from `RubyIndexer`, so this class normalizes host objects back to
      # the backend-neutral model before they leave the adapter:
      #
      # - singleton owners are named `Foo::<Foo>` and become `Foo::<Class:Foo>`
      # - `attr_*` members are named after the reader (`age()`) and writers are not separate members; the adapter
      #   derives the writer (`age=`) from `AttrWriterDefinition`/`AttrAccessorDefinition`
      # - comments are `Rubydex::Comment` objects that keep their `#` marker
      # - ancestors include built-in placeholders (`Object`, `Kernel`, `BasicObject`) that are not backed by an
      #   indexed document; those are dropped so ancestors match what `RubyIndexer` returns for the same files
      #
      # As with the RubyIndexer backend, every method degrades to `nil`/`[]` instead of raising (NFR-R1).
      class RubydexAdapter < Adapter
        SINGLETON_SUFFIX = /::<(?!(?:Class:))([^:>]+)>\z/
        BUILT_IN_URI = "rubydex:built-in"

        PARAMETER_KINDS = {
          Rubydex::Signature::PositionalParameter => :required,
          Rubydex::Signature::PostParameter => :required,
          Rubydex::Signature::OptionalPositionalParameter => :optional,
          Rubydex::Signature::RestPositionalParameter => :rest,
          Rubydex::Signature::KeywordParameter => :keyword,
          Rubydex::Signature::OptionalKeywordParameter => :keyword_optional,
          Rubydex::Signature::RestKeywordParameter => :keyword_rest,
          Rubydex::Signature::ForwardParameter => :forwarding,
          Rubydex::Signature::BlockParameter => :block
        }.freeze

        READER_DEFINITIONS = [Rubydex::AttrReaderDefinition, Rubydex::AttrAccessorDefinition].freeze
        WRITER_DEFINITIONS = [Rubydex::AttrWriterDefinition, Rubydex::AttrAccessorDefinition].freeze

        def initialize(graph, log: nil)
          super(log: log)
          @graph = graph
        end

        def method_definitions(owner, name, singleton: false)
          namespace = namespace_for(owner, singleton: singleton)
          return [] unless namespace

          method_definitions_for(namespace, name)
        rescue => e
          log_failure("method_definitions(#{owner.inspect}, #{name.inspect})", e)
        end

        def attribute_definitions(owner, name)
          namespace = namespace_for(owner, singleton: false)
          return [] unless namespace

          attribute_definitions_for(namespace, name)
        rescue => e
          log_failure("attribute_definitions(#{owner.inspect}, #{name.inspect})", e)
        end

        def constant_definitions(name)
          declaration = @graph[name.to_s]
          return [] unless constant_declaration?(declaration)

          declaration.definitions.map do |definition|
            definition_for(
              definition,
              declaration,
              name: declaration.name,
              kind: kind_for_declaration(declaration),
              owner: namespace_declaration?(declaration) ? nil : declaration.owner&.name
            )
          end
        rescue => e
          log_failure("constant_definitions(#{name.inspect})", e)
        end

        def resolve_constant(name, nesting)
          name = name.to_s
          return @graph.resolve_constant(name.delete_prefix("::"), [])&.name if name.start_with?("::")

          # Rubydex does not fall back to the top-level scope when a qualified name cannot be resolved relative to
          # the given nesting, so mirror `RubyIndexer#resolve` here.
          resolved = @graph.resolve_constant(name, sanitize_nesting(nesting)) || @graph.resolve_constant(name, [])
          resolved&.name
        rescue => e
          log_failure("resolve_constant(#{name.inspect}, #{nesting.inspect})", e)
          nil
        end

        def ancestors(fully_qualified_name)
          declaration = @graph[fully_qualified_name.to_s]
          return [] unless declaration.is_a?(Rubydex::Namespace)

          declaration.ancestors.select { |ancestor| indexed?(ancestor) }.map { |ancestor| normalize_name(ancestor.name) }
        rescue => e
          log_failure("ancestors(#{fully_qualified_name.inspect})", e)
        end

        def methods_of(owner, prefix: nil, singleton: false)
          method_candidates(owner, prefix: prefix, singleton: singleton, include_comments: true)
        end

        def completion_candidates(owner, prefix: nil, singleton: false)
          method_candidates(owner, prefix: prefix, singleton: singleton, include_comments: false)
        end

        def constant_candidates(prefix, nesting)
          prefix = prefix.to_s
          candidates, partial = constant_candidate_pool(prefix, nesting)

          candidates.filter_map do |declaration|
            next unless constant_declaration?(declaration)
            next unless partial.empty? || declaration.unqualified_name.start_with?(partial)

            definition_for(
              declaration.definitions.first,
              declaration,
              name: declaration.name,
              kind: kind_for_declaration(declaration),
              owner: namespace_declaration?(declaration) ? nil : declaration.owner&.name,
              include_comments: false
            )
          end.uniq { |definition| definition.name }
        rescue => e
          log_failure("constant_candidates(#{prefix.inspect}, #{nesting.inspect})", e)
        end

        def all_definitions(include_comments: true)
          @graph.declarations.filter_map do |declaration|
            definitions = declaration.definitions.to_a
            next if definitions.empty?
            next unless definitions.any? { |definition| definition.location.uri != BUILT_IN_URI }

            name = declaration_name(declaration)
            next if name.empty?

            definitions.map do |definition|
              definition_for(
                definition,
                declaration,
                name: name,
                kind: kind_for_declaration(declaration),
                owner: namespace_declaration?(declaration) ? nil : UNSET,
                include_comments: include_comments
              )
            end
          end.flatten
        rescue => e
          log_failure("all_definitions", e)
        end

        private

        # RubyIndexer stores singleton methods on a synthetic namespace named `Foo::<Class:Foo>`; Rubydex names it
        # `Foo::<Foo>`. The adapter keeps the RubyIndexer spelling everywhere (FR-M6-04).
        def namespace_for(owner, singleton:)
          return nil if owner.nil?

          name = singleton ? singleton_name(owner) : owner.to_s
          declaration = @graph[name]
          declaration if declaration.is_a?(Rubydex::Namespace)
        end

        def singleton_name(owner)
          "#{owner}::<#{owner.to_s.split("::").last}>"
        end

        # A writer lookup (`age=`) has no member of its own: Rubydex stores `attr_writer`/`attr_accessor` on the
        # reader-named member, so the writer is derived from it.
        def writer_member(namespace, name)
          member = namespace.find_member("#{name.to_s.delete_suffix("=")}()")
          member if member.is_a?(Rubydex::Method) && writer_capable?(member)
        end

        def method_definitions_for(namespace, name)
          name = name.to_s
          if name.end_with?("=")
            member = writer_member(namespace, name)
            return member ? [attribute_writer_definition(member, name.delete_suffix("="))] : []
          end

          declaration = namespace.find_member("#{name}()")
          return [] unless declaration.is_a?(Rubydex::Method)

          definitions = method_definition_list(declaration, name)
          if definitions.empty? && reader_capable?(declaration)
            definitions << attribute_reader_definition(declaration, name)
          end
          definitions
        end

        def attribute_definitions_for(namespace, name)
          name = name.to_s
          base = name.delete_suffix("=")
          declaration = namespace.find_member("#{base}()")
          return [] unless declaration.is_a?(Rubydex::Method)

          definitions = []
          definitions << attribute_reader_definition(declaration, base) if !name.end_with?("=") && reader_capable?(declaration)
          definitions << attribute_writer_definition(declaration, base) if writer_capable?(declaration)
          definitions
        end

        def method_candidates(owner, prefix:, singleton:, include_comments:)
          namespace = namespace_for(owner, singleton: singleton)
          return [] unless namespace

          collect_members(namespace).flat_map do |declaration|
            next [] unless declaration.is_a?(Rubydex::Method)

            candidate_definitions(declaration, include_comments: include_comments).select do |definition|
              prefix.nil? || definition.name.start_with?(prefix.to_s)
            end
          end
        rescue => e
          log_failure("method_candidates(#{owner.inspect}, prefix: #{prefix.inspect})", e)
        end

        # One definition per method-like name (`timeout`, `aliased`) plus the reader/writer names the definition
        # implies (`r`, `w=`, `a=`, ...). A member that carries both a real method and an `attr_*` definition keeps
        # the method for its base name, matching `RubyIndexer`'s duplicate handling.
        def candidate_definitions(declaration, include_comments:)
          base = declaration.unqualified_name.to_s.delete_suffix("()")
          definitions = method_definition_list(declaration, base, include_comments: include_comments)

          if reader_capable?(declaration)
            definitions << attribute_reader_definition(declaration, base, include_comments: include_comments)
          end

          if writer_capable?(declaration)
            definitions << attribute_writer_definition(declaration, base, include_comments: include_comments)
          end

          definitions
        end

        # Inherited members in ancestor order, first definition wins, matching `RubyIndexer`'s completion candidate
        # deduplication.
        def collect_members(namespace)
          seen = {}
          namespace.ancestors.each do |ancestor|
            next unless indexed?(ancestor)

            ancestor.members.each do |member|
              key = member.unqualified_name
              seen[key] = member unless seen.key?(key)
            end
          end
          seen.values
        end

        def method_definition_list(declaration, name, include_comments: true)
          declaration.definitions.filter_map do |definition|
            kind = method_definition_kind(definition)
            next unless kind

            definition_for(definition, declaration, name: name, kind: kind, include_comments: include_comments)
          end
        end

        def method_definition_kind(definition)
          case definition
          when Rubydex::MethodAliasDefinition
            :method_alias
          when Rubydex::MethodDefinition
            :method
          end
        end

        def attribute_reader_definition(declaration, name, include_comments: true)
          definition_for(
            declaration.definitions.first,
            declaration,
            name: name,
            kind: :attribute,
            include_comments: include_comments
          )
        end

        def attribute_writer_definition(declaration, base, include_comments: true)
          definition_for(
            declaration.definitions.first,
            declaration,
            name: "#{base}=",
            kind: :attribute,
            parameters: [Parameter.new(:value, :required)],
            include_comments: include_comments
          )
        end

        UNSET = Object.new

        def definition_for(definition, declaration, name:, kind:, owner: UNSET,
          parameters: nil, include_comments: true)
          location = definition.location
          name_location = definition.name_location || location

          Definition.new(
            name: name,
            owner: owner.equal?(UNSET) ? owner_name(declaration) : owner,
            kind: kind,
            visibility: visibility_for(declaration),
            uri: uri_for(location),
            location: convert_location(name_location),
            full_location: convert_location(location),
            file_name: file_name_for(location),
            comments: include_comments ? comments_for(definition) : nil,
            parameters: parameters || parameters_for(definition)
          )
        end

        def owner_name(declaration)
          owner = declaration.owner
          owner ? normalize_name(owner.name) : nil
        end

        def normalize_name(name)
          name.to_s.sub(SINGLETON_SUFFIX) { "::<Class:#{Regexp.last_match(1)}>" }
        end

        def comments_for(definition)
          definition.comments.map { |comment| comment.string.delete_prefix("#").delete_prefix(" ") }.join("\n")
        end

        def parameters_for(definition)
          return [] unless definition.respond_to?(:signatures)

          signature = definition.signatures.first
          return [] unless signature

          signature.parameters.map do |parameter|
            Parameter.new(parameter.name, PARAMETER_KINDS.fetch(parameter.class, :required))
          end
        end

        def visibility_for(declaration)
          declaration.respond_to?(:visibility) ? declaration.visibility : :public
        end

        def uri_for(location)
          URI(location.uri)
        rescue
          nil
        end

        def file_name_for(location)
          path = location.to_file_path
          path && File.basename(path)
        rescue
          nil
        end

        def convert_location(location)
          return nil unless location

          Location.new(
            start_line: location.start_line,
            start_column: location.start_column,
            end_line: location.end_line,
            end_column: location.end_column
          )
        end

        def sanitize_nesting(nesting)
          Array(nesting).reject { |part| part.to_s.start_with?("<") }
        end

        # Candidates for a possibly qualified prefix: `Nested::Thi` resolves `Nested` relative to the definition's
        # nesting and lists its members; a bare prefix lists everything reachable from the nesting (including
        # enclosing scopes). Mirrors `RubyIndexer#constant_completion_candidates`.
        def constant_candidate_pool(prefix, nesting)
          return [expression_candidates(sanitize_nesting(nesting)), prefix] unless prefix.include?("::")

          separator = prefix.rindex("::")
          namespace = prefix[0...separator]
          partial = prefix[(separator + 2)..].to_s
          candidates = if namespace.empty?
            expression_candidates([])
          else
            resolved = resolve_constant(namespace, nesting)
            resolved ? Array(@graph.complete_namespace_access(resolved, self_receiver: nil)) : []
          end

          [candidates, partial]
        end

        def expression_candidates(nesting)
          @graph.complete_expression(nesting, self_receiver: nil)
        rescue
          []
        end

        def constant_declaration?(declaration)
          declaration.is_a?(Rubydex::Class) || declaration.is_a?(Rubydex::Module) ||
            declaration.is_a?(Rubydex::Constant) || declaration.is_a?(Rubydex::ConstantAlias)
        end

        def namespace_declaration?(declaration)
          declaration.is_a?(Rubydex::Namespace)
        end

        def kind_for_declaration(declaration)
          case declaration
          when Rubydex::Class
            :class
          when Rubydex::Module
            :module
          when Rubydex::Constant, Rubydex::ConstantAlias
            :constant
          when Rubydex::Method
            :method
          else
            :unknown
          end
        end

        # Rubydex names method declarations after the member (`age()`, `age=()`); other declarations use their name.
        def declaration_name(declaration)
          return declaration.name.to_s unless declaration.is_a?(Rubydex::Method)

          declaration.unqualified_name.to_s.delete_suffix("()")
        end

        def reader_capable?(declaration)
          declaration.definitions.any? { |definition| READER_DEFINITIONS.any? { |klass| definition.is_a?(klass) } }
        end

        def writer_capable?(declaration)
          declaration.definitions.any? { |definition| WRITER_DEFINITIONS.any? { |klass| definition.is_a?(klass) } }
        end

        # Built-in placeholders (`Object`, `Kernel`, `BasicObject`, ...) exist even when no RBS/core document was
        # indexed. They are backed only by `rubydex:built-in` definitions, so they are not ancestors of anything from
        # the point of view of the add-on. Synthetic namespaces without definitions (singleton classes, for example)
        # are kept: their methods carry the definitions.
        def indexed?(declaration)
          definitions = declaration.definitions.to_a
          definitions.empty? || definitions.any? { |definition| definition.location.uri != BUILT_IN_URI }
        end

        def log_failure(operation, error)
          @log&.error("Indexer #{operation} failed: #{error.class}: #{error.message}")
          []
        end
      end
    end
  end
end
