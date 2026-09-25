# frozen_string_literal: true

require_relative "../documentation"
require_relative "../types"

module RubyLsp
  module Yard
    module Domains
      # Maps a namespace to the DSL domains bound to it (FR-M7-02). `@!domain` directives on a class or module comment
      # bind the listed types; `.solargraph.yml` `domains` bind workspace-wide (FR-M7-03). A `Class<X>` domain is a
      # class context (singleton methods), a plain `X` an instance context. Built lazily from indexed comments and
      # invalidated when watched files change. Never raises: failures degrade to no domains (NFR-R1).
      class Registry
        def initialize(adapter, extractor: nil, log: nil, enabled: true, global: [])
          @adapter = adapter
          @extractor = extractor || Documentation::TagExtractor.new(log: log)
          @log = log
          @enabled = enabled
          @global = global
          @local = nil
          @parsers = {}
          @mutex = Mutex.new

          adapter.subscribe { invalidate } if enabled
        end

        def enabled?
          @enabled
        end

        # `[owner, singleton]` descriptors for the domains bound to `namespace`.
        def domains_for(namespace)
          return [] unless @enabled

          global = global_entries.flat_map { |entry| descriptors(entry, nil) }
          local = local_entries(namespace).flat_map { |entry| descriptors(entry, namespace) }
          (global + local).uniq
        end

        def invalidate
          @mutex.synchronize { @local = nil }
        end

        private

        # FR-M7-03: `.solargraph.yml` domains are workspace-wide; the callable lets the config refresh its mtime
        # without rebuilding the registry.
        def global_entries
          value = @global.respond_to?(:call) ? @global.call : @global
          Array(value)
        end

        def local_entries(namespace)
          local.fetch(namespace.to_s, [])
        end

        def local
          @mutex.synchronize { return @local if @local }

          @local = {}
          definitions.each do |definition|
            comments = definition.comments
            next unless comments&.include?("@!domain")

            raw = @extractor.extract(comments)
            types = raw.directives.select { |directive| directive.kind == :domain }.flat_map(&:types)
            next if types.empty?

            key = (definition.owner || definition.name).to_s
            (@local[key] ||= []).concat(types)
          end
          @local
        end

        def definitions
          @adapter.all_definitions
        rescue => e
          @log&.error("Domain scan failed: #{e.class}: #{e.message}")
          []
        end

        def descriptors(type_string, namespace)
          collect(parser_for(namespace).parse(type_string.to_s))
        rescue
          []
        end

        def collect(type)
          case type
          when Types::Singleton
            [{owner: type.name.to_s, singleton: true}]
          when Types::Instance, Types::Ref
            name = Types.name_of(type)
            name ? [{owner: name.to_s, singleton: false}] : []
          when Types::Union
            type.types.flat_map { |member| collect(member) }
          else
            []
          end
        end

        def parser_for(namespace)
          key = namespace.to_s
          @parsers[key] ||= Types::Parser.new(
            resolver: ->(name, nesting) { @adapter.resolve_constant(name, nesting) },
            nesting: key.split("::")
          )
        end
      end
    end
  end
end
