# frozen_string_literal: true

module RubyLsp
  module Yard
    module Authoring
      # Resolves the constant under the cursor inside a YARD comment and turns it into hover content or definition
      # targets (FR-M1-14, FR-M4-P6). Never raises (NFR-R2).
      class TypeLookup
        include RubyLsp::Requests::Support::Common

        def initialize(context, adapter:, log: nil)
          @context = context
          @adapter = adapter
          @log = log
        end

        # The resolved fully qualified name, or nil when the cursor is not on a resolvable constant.
        def resolved
          return @resolved if defined?(@resolved)

          name = @context.constant_at_cursor
          @resolved = (name && @adapter) ? @adapter.resolve_constant(name, @context.nesting) : nil
        end

        def hover_markdown
          name = resolved
          return nil unless name

          primary = definitions(name).first
          return nil unless primary

          header = "```ruby\n#{declaration(primary)}\n```"
          comments = primary.comments.to_s.strip
          comments.empty? ? header : "#{header}\n\n#{comments}"
        rescue => e
          @log&.error("Comment hover failed: #{e.class}: #{e.message}")
          nil
        end

        def links
          name = resolved
          return [] unless name

          definitions(name).filter_map { |definition| link_for(definition) }
        rescue => e
          @log&.error("Comment definition failed: #{e.class}: #{e.message}")
          []
        end

        private

        def definitions(name)
          @definitions ||= {}
          @definitions[name] ||= @adapter ? @adapter.constant_definitions(name) : []
        end

        def declaration(definition)
          case definition.kind
          when :module then "module #{definition.name}"
          when :class then "class #{definition.name}"
          else definition.name
          end
        end

        def link_for(definition)
          location = definition.full_location || definition.location
          selection = definition.location || location
          return nil unless definition.uri && location && selection

          Interface::LocationLink.new(
            target_uri: definition.uri.to_s,
            target_range: range_from_location(location),
            target_selection_range: range_from_location(selection)
          )
        end
      end
    end
  end
end
