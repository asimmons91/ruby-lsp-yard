# frozen_string_literal: true

require "rbs"

require_relative "../types"

module RubyLsp
  module Yard
    module Rbs
      # Converts RBS type expressions into the internal type model (FR-M3-01). Interfaces become duck types,
      # aliases are expanded with a depth cap, and intersections are approximated as unions. Conversion never
      # raises: anything unrepresentable degrades to `Unknown` (NFR-R1).
      class Converter
        MAX_DEPTH = 8

        def initialize(environment: nil, builder: nil)
          @environment = environment
          @builder = builder
        end

        def convert(type, depth: 0)
          return Types::UNKNOWN if depth > MAX_DEPTH || type.nil?

          base = base_types[type.class]
          return base if base

          case type
          when ::RBS::Types::Variable then Types::TypeVar.new(type.name)
          when ::RBS::Types::ClassInstance then convert_class_instance(type, depth)
          when ::RBS::Types::ClassSingleton then Types::Singleton.new(strip(type.name))
          when ::RBS::Types::Interface then convert_interface(type)
          when ::RBS::Types::Union then Types.union(type.types.map { |member| convert(member, depth: depth + 1) })
          when ::RBS::Types::Intersection then Types.union(type.types.map { |member| convert(member, depth: depth + 1) })
          when ::RBS::Types::Optional then Types.union([convert(type.type, depth: depth + 1), Types::NIL_TYPE])
          when ::RBS::Types::Tuple then Types::Tuple.new(type.types.map { |member| convert(member, depth: depth + 1) })
          when ::RBS::Types::Record then convert_record(type, depth)
          when ::RBS::Types::Proc then Types::Instance.new("Proc")
          when ::RBS::Types::Literal then Types::Literal.new(type.literal)
          when ::RBS::Types::Alias then convert_alias(type, depth)
          else Types::UNKNOWN
          end
        rescue
          Types::UNKNOWN
        end

        private

        # An explicit map instead of a `case` because some base constants are version dependent (`untyped` was a
        # separate class in older RBS releases, `Bases::Any` today).
        def base_types
          @base_types ||= {
            ::RBS::Types::Bases::Any => Types::UNTYPED,
            ::RBS::Types::Bases::Nil => Types::NIL_TYPE,
            ::RBS::Types::Bases::Bool => Types::BOOLEAN,
            ::RBS::Types::Bases::Void => Types::VOID,
            ::RBS::Types::Bases::Self => Types::SELF,
            ::RBS::Types::Bases::Bottom => Types::VOID,
            ::RBS::Types::Bases::Top => Types::UNKNOWN,
            ::RBS::Types::Bases::Instance => Types::UNKNOWN,
            ::RBS::Types::Bases::Class => Types::UNKNOWN
          }
        end

        def convert_class_instance(type, depth)
          args = type.args.map { |argument| convert(argument, depth: depth + 1) }
          name = strip(type.name)
          args.empty? ? Types::Instance.new(name) : Types::Instance.new(name, args)
        end

        # FR-M3-01: RBS interfaces are structural, so they map to the duck type the model already has.
        def convert_interface(type)
          methods = interface_method_names(type.name)
          methods.empty? ? Types::UNKNOWN : Types::Duck.new(methods)
        end

        def interface_method_names(name)
          entry = @environment&.interface_decls&.[](absolute(name))
          return [] unless entry

          entry.decl.members.filter_map do |member|
            member.name.name.to_s if member.is_a?(::RBS::AST::Members::MethodDefinition)
          end
        rescue
          []
        end

        # FR-M3-01: `Hash{ key: String }` records keep their field names as literal keys.
        def convert_record(type, depth)
          keys = type.fields.keys.map { |field| Types::Literal.new(field) }
          values = type.fields.values.map { |field| convert(field, depth: depth + 1) }
          type.optional_fields.each do |field, value|
            keys << Types::Literal.new(field)
            values << Types.union([convert(value, depth: depth + 1), Types::NIL_TYPE])
          end
          Types::HashOf.new(Types.union(keys), Types.union(values))
        rescue
          Types::UNKNOWN
        end

        def convert_alias(type, depth)
          return Types::UNKNOWN if depth > MAX_DEPTH || @builder.nil?

          convert(@builder.expand_alias(absolute(type.name)), depth: depth + 1)
        rescue
          Types::UNKNOWN
        end

        # Standalone rbs-inline declarations carry relative names, while the loaded environment is keyed by absolute
        # ones; core/stdlib aliases and interfaces are declared at the top level or under absolute namespaces.
        def absolute(name)
          name.absolute? ? name : name.absolute!
        end

        # Internal names never carry a leading `::` (the indexer adapter resolves them without one).
        def strip(name)
          name.to_s.delete_prefix("::")
        end
      end
    end
  end
end
