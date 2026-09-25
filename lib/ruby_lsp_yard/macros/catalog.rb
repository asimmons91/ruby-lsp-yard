# frozen_string_literal: true

require_relative "expander"

module RubyLsp
  module Yard
    module Macros
      # Collects named macro definitions from indexed comments (FR-M7-01). A macro definition is a `@!macro` directive
      # with macro data; its `[new]`/`[attach]` flags are metadata. Named macros are expanded wherever a docstring
      # invokes them with `@macro name` / `@!macro name`. Built lazily from the index (not by re-parsing files) and
      # invalidated when watched files change. Never raises: failures degrade to no macros (NFR-R1).
      class Catalog
        Macro = Struct.new(:name, :data, :flags) do
          def attach?
            flags.include?("attach")
          end

          def new?
            flags.include?("new")
          end
        end

        INVOCATION = /\A(\s*)@!?macro\s+(\S+)\s*\z/
        EXPANSION_LIMIT = 10

        def initialize(adapter, extractor: nil, log: nil, enabled: true)
          @adapter = adapter
          @extractor = extractor || Documentation::TagExtractor.new(log: log)
          @log = log
          @enabled = enabled
          @macros = nil
          @mutex = Mutex.new
          @expander = Expander.new
        end

        def enabled?
          @enabled
        end

        # The macro data registered under `name`, or nil.
        def macro(name)
          return nil unless @enabled

          macros[name.to_s]
        end

        # Expands `@macro name` invocations in a docstring (FR-M7-01). Anonymous macros and macro definitions are left
        # in place; expansion recurses through macros that reference other macros with cycle detection (NFR-R3).
        def expand_comments(comments, method_name: nil)
          text = comments.to_s
          return comments unless @enabled
          return comments unless text.include?("@macro") || text.include?("@!macro")

          visited = []
          EXPANSION_LIMIT.times do
            expanded = expand_once(text, method_name: method_name, visited: visited)
            break if expanded == text

            text = expanded
          end
          text
        rescue => e
          @log&.error("Macro expansion failed: #{e.class}: #{e.message}")
          comments
        end

        def invalidate
          @mutex.synchronize { @macros = nil }
        end

        private

        def expand_once(text, method_name:, visited:)
          lines = text.lines
          changed = false

          expanded = lines.each_with_index.map do |line, index|
            match = INVOCATION.match(line)
            next line unless match
            next line if definition?(lines, index)

            name = match[2]
            data = macro(name)
            if data.nil? || visited.include?(name)
              next line
            end

            visited << name
            changed = true
            expand_data(data, method_name, match[1])
          end.join

          changed ? expanded : text
        end

        # `@!macro name` followed by indented lines is a macro definition (YARD reads the indented block as the macro
        # body), so it must not be expanded in place. `[new]`/`[attach]` definitions never match {INVOCATION}.
        def definition?(lines, index)
          indentation = indent_width(lines[index])
          lines[(index + 1)..].to_a.each do |candidate|
            next if candidate.to_s.strip.empty?

            return indent_width(candidate) > indentation
          end
          false
        end

        def indent_width(line)
          line.to_s[/\A[ \t]*/].to_s.length
        end

        def expand_data(data, method_name, indentation)
          macro_data = data.respond_to?(:data) ? data.data : data
          expanded = @expander.expand(macro_data, params: [method_name].compact, source: "")
          expanded.lines.map do |line|
            line.strip.empty? ? "\n" : "#{indentation}#{line}"
          end.join
        end

        def macros
          @mutex.synchronize { return @macros if @macros }

          @macros = {}
          definitions.each do |definition|
            comments = definition.comments
            next unless comments&.include?("@!macro")

            raw = @extractor.extract(comments)
            raw.directives.each do |directive|
              next unless directive.kind == :macro
              next if directive.name.to_s.empty? || directive.text.to_s.empty?

              @macros[directive.name.to_s] = Macro.new(
                name: directive.name.to_s,
                data: directive.text.to_s,
                flags: Array(directive.types)
              )
            end
          end
          @macros
        end

        def definitions
          @adapter.all_definitions
        rescue => e
          @log&.error("Macro catalog scan failed: #{e.class}: #{e.message}")
          []
        end
      end
    end
  end
end
