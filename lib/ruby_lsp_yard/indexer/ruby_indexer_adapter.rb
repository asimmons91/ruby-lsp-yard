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

        def constant_definitions(name)
          entries = Array(@index[name]).select do |entry|
            entry.is_a?(RubyIndexer::Entry::Namespace) || entry.is_a?(RubyIndexer::Entry::Constant)
          end

          map_entries(entries)
        rescue => e
          log_failure("constant_definitions(#{name.inspect})", e)
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

        def completion_candidates(owner, prefix: nil, singleton: false)
          entries = @index.method_completion_candidates(prefix, receiver_name(owner, singleton: singleton))
          map_entries(entries, include_comments: false)
        rescue => e
          log_failure("completion_candidates(#{owner.inspect}, prefix: #{prefix.inspect})", e)
        end

        def constant_candidates(prefix, nesting)
          entries = @index.constant_completion_candidates(prefix.to_s, Array(nesting))
          map_entries(entries.flatten, include_comments: false)
        rescue => e
          log_failure("constant_candidates(#{prefix.inspect}, #{nesting.inspect})", e)
        end

        def all_definitions(include_comments: true)
          @index.names.flat_map do |name|
            map_entries(Array(@index[name]), include_comments: include_comments)
          end
        rescue => e
          log_failure("all_definitions", e)
        end

        private

        # RubyIndexer stores singleton methods on a synthetic namespace named `Foo::<Class:Foo>`.
        def receiver_name(owner, singleton:)
          return owner unless singleton

          unqualified_name = owner.split("::").last
          "#{owner}::<Class:#{unqualified_name}>"
        end

        def map_entries(entries, include_comments: true)
          Array(entries).map { |entry| definition_for(entry, include_comments: include_comments) }
        end

        def definition_for(entry, include_comments: true)
          Definition.new(
            name: entry.name,
            owner: entry.respond_to?(:owner) ? entry.owner&.name : nil,
            kind: kind_for(entry),
            visibility: entry.visibility,
            uri: entry.uri,
            location: location_for(entry),
            full_location: full_location_for(entry),
            file_name: entry.file_name,
            comments: include_comments ? entry.comments : nil,
            parameters: parameters_for(entry)
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
          when RubyIndexer::Entry::Class
            :class
          when RubyIndexer::Entry::Module
            :module
          when RubyIndexer::Entry::Constant
            :constant
          else
            :unknown
          end
        end

        def parameters_for(entry)
          return [Parameter.new(:value, :required)] if entry.is_a?(RubyIndexer::Entry::Accessor) && entry.name.end_with?("=")

          signatures = entry.respond_to?(:signatures) ? entry.signatures : nil
          first_signature = signatures&.first
          return [] unless first_signature

          first_signature.parameters.map do |parameter|
            Parameter.new(parameter.name, parameter_kind(parameter))
          end
        end

        def parameter_kind(parameter)
          case parameter
          when RubyIndexer::Entry::OptionalParameter
            :optional
          when RubyIndexer::Entry::KeywordParameter
            :keyword
          when RubyIndexer::Entry::OptionalKeywordParameter
            :keyword_optional
          when RubyIndexer::Entry::RestParameter
            :rest
          when RubyIndexer::Entry::KeywordRestParameter
            :keyword_rest
          when RubyIndexer::Entry::BlockParameter
            :block
          when RubyIndexer::Entry::ForwardingParameter
            :forwarding
          else
            :required
          end
        end

        def location_for(entry)
          convert_location(entry.name_location)
        end

        def full_location_for(entry)
          convert_location(entry.location)
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

        def log_failure(operation, error)
          @log&.error("Indexer #{operation} failed: #{error.class}: #{error.message}")
          []
        end
      end
    end
  end
end
