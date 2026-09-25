# frozen_string_literal: true

require "prism"

require_relative "../documentation"
require_relative "../indexer/definition"
require_relative "../signature"
require_relative "catalog"
require_relative "expander"

module RubyLsp
  module Yard
    module Macros
      # Applies `@!macro` expansions to DSL call sites and exposes the resulting definitions (FR-M7-01). A macro is
      # applied only to calls that resolve to the method where the macro was defined (the Solargraph rule), which also
      # covers inheritance through `include`, `extend` and superclasses because resolution goes through the adapter.
      # Only expansions containing `@!method`, `@!attribute` or `@!parse` produce definitions. Never raises; failures
      # degrade to no definitions (NFR-R1).
      class Store
        def initialize(adapter, catalog: nil, builder: nil, extractor: nil, log: nil, enabled: true)
          @adapter = adapter
          @log = log
          @enabled = enabled
          @extractor = extractor || Documentation::TagExtractor.new(log: log)
          @catalog = catalog || Catalog.new(adapter, extractor: @extractor, log: log, enabled: enabled)
          @builder = builder || Documentation::SignatureBuilder.new(adapter, log: log)
          @expander = Expander.new
          @entries = {}
          @attached = {}
          @mutex = Mutex.new

          adapter.subscribe { invalidate } if enabled
        end

        def enabled?
          @enabled
        end

        # Expands named macro invocations in a docstring before tag extraction (FR-M7-01).
        def expand_comments(comments, method_name: nil)
          @catalog.expand_comments(comments, method_name: method_name)
        end

        # The virtual signatures generated for `owner`'s DSL calls, keyed by method name. `singleton` selects the
        # resulting method kind (`@!method self.x` is a singleton method even when the call is in a class body).
        def entries_for(owner, singleton: false)
          return {} unless @enabled

          all_entries(owner).each_with_object({}) do |((name, entry_singleton), signature), result|
            result[name] = signature if entry_singleton == singleton
          end
        end

        # The virtual signature for `name` on `owner`, or nil.
        def lookup(owner, name, singleton: false)
          entries_for(owner, singleton: singleton)[name.to_s]
        end

        def invalidate
          @mutex.synchronize do
            @entries.clear
            @attached.clear
          end
          @catalog.invalidate
        end

        private

        def all_entries(owner)
          key = owner.to_s
          cached = @mutex.synchronize { @entries.fetch(key, nil) }
          return cached if cached

          built = build_entries(key)
          @mutex.synchronize { @entries[key] = built }
          built
        end

        def build_entries(owner)
          entries = {}

          owner_files(owner).each do |uri, path|
            source = read_source(path)
            next unless source

            result = Prism.parse(source)
            next unless result.success?

            visit(result.value, owner, source, uri, entries, [])
          end

          entries
        rescue => e
          @log&.error("Macro expansion failed for #{owner}: #{e.class}: #{e.message}")
          {}
        end

        # Walks class-level statements (method bodies are not descended into, mirroring the diagnostics scanner).
        def visit(node, owner, source, uri, entries, nesting)
          case node
          when Prism::ProgramNode
            visit(node.statements, owner, source, uri, entries, nesting)
          when Prism::StatementsNode
            node.body.each { |child| visit(child, owner, source, uri, entries, nesting) }
          when Prism::ClassNode, Prism::ModuleNode
            child_nesting = nesting + node.constant_path.slice.split("::")
            visit(node.body, owner, source, uri, entries, child_nesting)
          when Prism::SingletonClassNode
            visit(node.body, owner, source, uri, entries, nesting)
          when Prism::CallNode
            visit_call(node, owner, source, uri, entries, nesting)
          end
        end

        def visit_call(node, owner, source, uri, entries, nesting)
          if nesting.join("::") == owner && (node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode))
            expand_call(node, owner, source, uri, entries)
          end

          block = node.block
          if block.is_a?(Prism::BlockNode) && block.body
            visit(block.body, owner, source, uri, entries, nesting)
          end
        end

        def expand_call(node, owner, source, uri, entries)
          name = node.message.to_s
          return if name.empty?

          macros = attached_macros(owner, name, singleton: true)
          return if macros.empty?

          params = [name] + Array(node.arguments&.arguments).map { |argument| argument_source(argument) }
          source_line = source.lines[node.location.start_line - 1].to_s.strip
          location = location_for(node)

          macros.each do |data|
            expanded = @expander.expand(data, params: params, source: source_line)
            expanded = @catalog.expand_comments(expanded, method_name: name)
            raw = @extractor.extract(expanded)
            @builder.apply_directives(entries, owner: owner, raw: raw, uri: uri, location: location)
          end
        end

        # The attached macro data for the method a DSL call resolves to. `singleton` is true for calls in class bodies
        # (they resolve to class methods, as in `def self.property`).
        def attached_macros(owner, name, singleton:)
          key = [owner, name, singleton]
          cached = @mutex.synchronize { @attached.fetch(key, nil) }
          return cached if cached

          macros = @adapter.method_definitions(owner, name, singleton: singleton).filter_map do |definition|
            attached_macro(definition)
          end.uniq
          @mutex.synchronize { @attached[key] = macros }
          macros
        rescue => e
          @log&.error("Attached macro lookup failed for #{owner}.#{name}: #{e.class}: #{e.message}")
          []
        end

        # YARD attaches a macro when it carries the `attach` flag or is defined on a class method.
        def attached_macro(definition)
          comments = definition.comments
          return nil unless comments&.include?("@!macro")

          raw = @extractor.extract(comments)
          singleton = definition.owner.to_s.include?("::<Class:")
          raw.directives.each do |directive|
            next unless directive.kind == :macro
            next if directive.text.to_s.empty?
            next unless directive.types.include?("attach") || singleton

            return directive.text.to_s
          end
          nil
        end

        def owner_files(owner)
          files = {}
          @adapter.constant_definitions(owner).each do |definition|
            uri = definition.uri
            path = path_for(uri)
            files[uri.to_s] = [uri, path] if uri && path
          end
          files.values
        rescue => e
          @log&.error("Macro file lookup failed for #{owner}: #{e.class}: #{e.message}")
          []
        end

        def path_for(uri)
          return nil unless uri.respond_to?(:scheme) && uri.scheme == "file"

          path = uri.respond_to?(:full_path) ? uri.full_path : URI::DEFAULT_PARSER.unescape(uri.path)
          path if path && File.file?(path)
        rescue
          nil
        end

        def read_source(path)
          File.read(path, encoding: Encoding::UTF_8)
        rescue
          nil
        end

        def argument_source(node)
          case node
          when Prism::SymbolNode, Prism::StringNode
            node.unescaped
          when Prism::IntegerNode, Prism::FloatNode
            node.value.to_s
          else
            node.slice
          end
        end

        def location_for(node)
          location = node.respond_to?(:message_loc) ? node.message_loc : nil
          location ||= node.location
          return nil unless location

          Indexer::Location.new(
            start_line: location.start_line,
            start_column: location.start_column,
            end_line: location.end_line,
            end_column: location.end_column
          )
        end
      end
    end
  end
end
