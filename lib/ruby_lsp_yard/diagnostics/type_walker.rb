# frozen_string_literal: true

require_relative "../types"

module RubyLsp
  module Yard
    module Diagnostics
      # Shared traversal helpers for diagnostics: enumerating every type expression in a {Documentation::RawDoc}
      # (including overloads and directive docstrings), finding unresolved constant names in a parsed type, and the
      # conservative literal-vs-declared compatibility check used by the off-by-default mismatch rules.
      module TypeWalker
        # One type expression found in a docstring. `text` is the raw YARD type string, `tag` the innermost tag
        # reference (`@param key`), and `label` the tag with any enclosing `@overload` prefix for messages.
        TypeRef = Struct.new(:text, :tag, :label)

        # YARD's generic type parameters (`Array<T>`, `Hash<K, V>`) cannot resolve and are not reported. RBS
        # interface names (`_ToS`) are skipped too.
        TYPE_VARIABLE = /\A[A-Z]\z/

        class << self
          # Yields a {TypeRef} for every type expression in `raw`, recursively through overloads and directive
          # docstrings.
          def each_type_string(raw, prefix: nil, &block)
            return unless raw

            raw.params.each { |tag| yield_types(tag.types, "@param #{tag.name}", prefix, &block) }
            raw.yield_params.each { |tag| yield_types(tag.types, "@yieldparam #{tag.name}", prefix, &block) }
            raw.returns.each { |tag| yield_types(tag.types, "@return", prefix, &block) }
            raw.yield_returns.each { |tag| yield_types(tag.types, "@yieldreturn", prefix, &block) }
            raw.raises.each { |tag| yield_types(tag.types, "@raise", prefix, &block) }
            raw.options.each { |tag| yield_types(tag.types, "@option #{tag.key || tag.name}", prefix, &block) }

            raw.overloads.each do |overload|
              each_type_string(overload.doc, prefix: combine(prefix, "@overload #{overload.signature}"), &block)
            end

            raw.directives.each do |directive|
              # `RawDirective#types` on an attribute directive holds YARD's `[r]`/`[w]` accessor flags, not types.
              next unless directive.doc

              each_type_string(directive.doc, prefix: combine(prefix, "@!#{directive.kind}"), &block)
            end
          end

          # The names in `type` that do not resolve relative to `nesting`. Type variables and RBS interface names are
          # skipped so YARD's loose generic notation does not produce warnings (FR-M5-01).
          def unresolved_names(type, resolver:, nesting:)
            return [] unless resolver

            names = []
            collect_unresolved(type, resolver, nesting, names)
            names.uniq
          end

          # A conservative check that `actual` can satisfy `declared`. Unknown, untyped, `self`, `void`, duck types
          # and type variables never conflict. Subclasses satisfy their ancestors when the adapter can say so.
          def compatible?(declared, actual, adapter: nil)
            return true if declared.nil? || actual.nil?
            return true if declared.is_a?(Types::Unknown) || actual.is_a?(Types::Unknown)
            return true if declared.is_a?(Types::TypeVar) || declared.is_a?(Types::Duck)
            return true if special_non_conflicting?(declared)
            if declared.is_a?(Types::Union)
              return declared.types.any? { |member| compatible?(member, actual, adapter: adapter) }
            end
            if actual.is_a?(Types::Union)
              return actual.types.all? { |member| compatible?(declared, member, adapter: adapter) }
            end

            actual = normalize_actual(actual)

            case declared
            when Types::Special
              special_matches?(declared, actual)
            when Types::Literal
              literal_matches?(declared, actual)
            when Types::Instance, Types::Singleton
              named_matches?(declared, actual, adapter: adapter)
            when Types::HashOf
              actual.is_a?(Types::HashOf) || instance_named?(actual, "Hash")
            when Types::Tuple
              actual.is_a?(Types::Tuple) || instance_named?(actual, "Array")
            else
              true
            end
          end

          private

          def yield_types(types, tag, prefix, &block)
            Array(types).each { |type| yield TypeRef.new(type.to_s, tag, combine(prefix, tag)) }
          end

          def combine(prefix, text)
            prefix ? "#{prefix} #{text}" : text
          end

          def collect_unresolved(type, resolver, nesting, names)
            case type
            when Types::Ref
              add_unresolved(type.name, resolver, nesting, names)
            when Types::Instance, Types::Singleton
              add_unresolved(type.name, resolver, nesting, names)
              Array(type.type_args).each { |argument| collect_unresolved(argument, resolver, nesting, names) }
            when Types::Union, Types::Tuple
              type.types.each { |member| collect_unresolved(member, resolver, nesting, names) }
            when Types::HashOf
              collect_unresolved(type.key, resolver, nesting, names)
              collect_unresolved(type.value, resolver, nesting, names)
            end
          end

          def add_unresolved(name, resolver, nesting, names)
            name = name.to_s
            return if name.empty? || name.match?(TYPE_VARIABLE) || name.start_with?("_")
            return if resolver.call(name, nesting)

            names << name
          end

          def special_non_conflicting?(type)
            type.is_a?(Types::Special) && %i[self void untyped].include?(type.name)
          end

          def special_matches?(declared, actual)
            case declared.name
            when :nil then actual.is_a?(Types::Special) && actual.name == :nil
            when :boolean then boolean_actual?(actual)
            else true
            end
          end

          def boolean_actual?(actual)
            (actual.is_a?(Types::Special) && actual.name == :boolean) ||
              (actual.is_a?(Types::Literal) && (actual.value == true || actual.value == false))
          end

          def literal_matches?(declared, actual)
            return declared.value == actual.value if actual.is_a?(Types::Literal)

            # A declared literal (`:foo`, `"bar"`, `1`) is satisfied by the literal's class instance.
            expected = Types.literal_class(declared)
            return true if expected.is_a?(Types::Unknown)

            compatible?(expected, actual)
          end

          def named_matches?(declared, actual, adapter:)
            if declared.is_a?(Types::Singleton)
              return actual.is_a?(Types::Singleton) && actual.name == declared.name
            end

            if actual.is_a?(Types::Special)
              # `nil` and booleans are their own specials; `self`/`untyped` are unknown and never conflict.
              return !%i[nil boolean].include?(actual.name)
            end
            return true unless actual.is_a?(Types::Instance)

            expected = declared.name
            return true if actual.name == expected
            return false unless adapter

            adapter.ancestors(actual.name).include?(expected)
          end

          # Literals are treated as instances of their class; `nil`/booleans stay special.
          def normalize_actual(actual)
            case actual
            when Types::Literal
              case actual.value
              when nil then Types::NIL_TYPE
              when true, false then Types::BOOLEAN
              else Types.literal_class(actual)
              end
            else
              actual
            end
          end

          def instance_named?(type, name)
            type.is_a?(Types::Instance) && type.name == name
          end
        end
      end
    end
  end
end
