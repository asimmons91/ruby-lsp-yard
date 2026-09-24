# frozen_string_literal: true

require "ruby_indexer/ruby_indexer"

require_relative "adapter"
require_relative "definition"

module RubyLsp
  module Yard
    module Indexer
      # Indexer Adapter for Ruby LSP 0.26.x, backed by `RubyIndexer` (FR-M0-04).
      class RubyIndexerAdapter < Adapter
        def initialize(index, log: nil)
          super(log: log)
          @index = index
        end

        def method_definitions(owner, name, singleton: false)
          entries = @index.resolve_method(name, receiver_name(owner, singleton: singleton))
          map_entries(entries)
        rescue => e
          log_failure("method_definitions(#{owner.inspect}, #{name.inspect})", e)
        end

        def attribute_definitions(owner, name)
          ancestors = @index.linearized_ancestors_of(owner)
          entries = Array(@index[name]) + Array(@index["#{name}="])
          entries.select! do |entry|
            entry.is_a?(RubyIndexer::Entry::Accessor) && ancestors.include?(entry.owner&.name)
          end

          map_entries(entries)
        rescue => e
          log_failure("attribute_definitions(#{owner.inspect}, #{name.inspect})", e)
        end

        def resolve_constant(name, nesting)
          @index.resolve(name, Array(nesting))&.first&.name
        rescue => e
          log_failure("resolve_constant(#{name.inspect}, #{nesting.inspect})", e)
          nil
        end

        def ancestors(fully_qualified_name)
          @index.linearized_ancestors_of(fully_qualified_name)
        rescue => e
          log_failure("ancestors(#{fully_qualified_name.inspect})", e)
        end

        def methods_of(owner, prefix: nil, singleton: false)
          entries = @index.method_completion_candidates(prefix, receiver_name(owner, singleton: singleton))
          map_entries(entries)
        rescue => e
          log_failure("methods_of(#{owner.inspect}, prefix: #{prefix.inspect})", e)
        end

        private

        # RubyIndexer stores singleton methods on a synthetic namespace named `Foo::<Class:Foo>`.
        def receiver_name(owner, singleton:)
          return owner unless singleton

          unqualified_name = owner.split("::").last
          "#{owner}::<Class:#{unqualified_name}>"
        end

        def map_entries(entries)
          Array(entries).map { |entry| definition_for(entry) }
        end

        def definition_for(entry)
          Definition.new(
            name: entry.name,
            owner: entry.owner&.name,
            kind: kind_for(entry),
            visibility: entry.visibility,
            uri: entry.uri,
            location: location_for(entry),
            comments: entry.comments
          )
        end

        def kind_for(entry)
          case entry
          when RubyIndexer::Entry::Accessor
            :attribute
          when RubyIndexer::Entry::MethodAlias
            :method_alias
          when RubyIndexer::Entry::Method
            :method
          else
            :unknown
          end
        end

        def location_for(entry)
          location = entry.name_location

          Location.new(
            start_line: location.start_line,
            start_column: location.start_column,
            end_line: location.end_line,
            end_column: location.end_column
          )
        end

        def log_failure(operation, error)
          @log&.error("Indexer #{operation} failed: #{error.class}: #{error.message}")
          []
        end
      end
    end
  end
end
