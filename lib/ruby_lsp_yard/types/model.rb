# frozen_string_literal: true

module RubyLsp
  module Yard
    # Internal type model (requirements §3.1). Types are immutable-by-convention value objects so they can be
    # compared and memoized cheaply.
    module Types
      # The result of failed inference or of a parse that cannot be represented. Never shown to users as a type.
      class Unknown
        def initialize
          freeze
        end
      end

      UNKNOWN = Unknown.new

      class Special < Struct.new(:name)
        def to_s
          name.to_s
        end
      end

      NIL_TYPE = Special.new(:nil)
      BOOLEAN = Special.new(:boolean)
      SELF = Special.new(:self)
      VOID = Special.new(:void)
      UNTYPED = Special.new(:untyped)

      class Instance < Struct.new(:name, :type_args)
        def initialize(name, type_args = [])
          super
        end
      end

      class Singleton < Struct.new(:name, :type_args)
        def initialize(name, type_args = [])
          super
        end
      end

      Union = Struct.new(:types)
      Tuple = Struct.new(:types)
      HashOf = Struct.new(:key, :value)
      Duck = Struct.new(:methods)
      Literal = Struct.new(:value)

      # A class name that could not be resolved relative to the documented definition (FR-M1-08). Not an error.
      Ref = Struct.new(:name)

      class << self
        # Builds a union, flattening nested unions, dropping `Unknown`s and duplicates. A single element collapses
        # to that element. Duck types from `#a, #b` are merged.
        def union(types)
          flat = types.flat_map { |type| type.is_a?(Union) ? type.types : [type] }
          flat.reject! { |type| unknown?(type) }
          flat.uniq!
          return UNKNOWN if flat.empty?
          return flat.first if flat.size == 1

          ducks, rest = flat.partition { |type| type.is_a?(Duck) }
          rest += [Duck.new(ducks.flat_map(&:methods).uniq)] unless ducks.empty?

          return rest.first if rest.size == 1

          Union.new(rest)
        end

        def unknown?(type)
          type.is_a?(Unknown)
        end

        def nil_type?(type)
          type == NIL_TYPE
        end

        def name_of(type)
          case type
          when Instance, Singleton, Ref
            type.name
          end
        end

        # Replaces `self` with `replacement` recursively, e.g. an `@return [self]` result resolved against the
        # receiver's inferred type (FR-M2-06).
        def substitute_self(type, replacement)
          case type
          when Special
            (type == SELF) ? replacement : type
          when Union
            union(type.types.map { |member| substitute_self(member, replacement) })
          when Instance
            return type if type.type_args.empty?

            Instance.new(type.name, type.type_args.map { |argument| substitute_self(argument, replacement) })
          when Singleton
            return type if type.type_args.empty?

            Singleton.new(type.name, type.type_args.map { |argument| substitute_self(argument, replacement) })
          when Tuple
            Tuple.new(type.types.map { |member| substitute_self(member, replacement) })
          when HashOf
            HashOf.new(substitute_self(type.key, replacement), substitute_self(type.value, replacement))
          else
            type
          end
        end

        # The type of the literal's class, for the stretch completion goal (requirements §3.1).
        def literal_class(type)
          return UNKNOWN unless type.is_a?(Literal)

          case type.value
          when ::String then Instance.new("String")
          when ::Symbol then Instance.new("Symbol")
          when ::Integer then Instance.new("Integer")
          when ::Float then Instance.new("Float")
          when true, false then BOOLEAN
          end
        end
      end
    end
  end
end
