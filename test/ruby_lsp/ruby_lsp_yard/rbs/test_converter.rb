# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/rbs"

module RubyLsp
  module Yard
    module Rbs
      class TestConverter < Minitest::Test
        class << self
          def loader
            @loader ||= begin
              loader = Loader.new(background: false)
              loader.start
              loader
            end
          end
        end

        def environment
          self.class.loader.environment
        end

        def builder
          self.class.loader.builder
        end

        def converter
          @converter ||= Converter.new(environment: environment, builder: builder)
        end

        def convert(source)
          converter.convert(::RBS::Parser.parse_type(source))
        end

        def test_converts_base_types
          assert_equal Types::UNTYPED, convert("untyped")
          assert_equal Types::NIL_TYPE, convert("nil")
          assert_equal Types::BOOLEAN, convert("bool")
          assert_equal Types::VOID, convert("void")
          assert_equal Types::SELF, convert("self")
          assert_equal Types::UNKNOWN, convert("top")
          assert_equal Types::UNKNOWN, convert("instance")
        end

        def test_converts_class_instances_with_generic_arguments
          assert_equal Types::Instance.new("String"), convert("::String")
          assert_equal Types::Instance.new("Array", [Types::Instance.new("String")]), convert("::Array[::String]")
          assert_equal Types::Singleton.new("String"), convert("singleton(::String)")
        end

        def test_converts_unions_optionals_intersections_and_tuples
          assert_equal Types.union([Types::Instance.new("String"), Types::NIL_TYPE]), convert("::String?")
          assert_equal(
            Types.union([Types::Instance.new("String"), Types::Instance.new("Integer")]),
            convert("::String | ::Integer")
          )
          assert_equal Types::Tuple.new([Types::Instance.new("String"), Types::Instance.new("Integer")]),
            convert("[ ::String, ::Integer ]")
        end

        def test_converts_literals_procs_and_records
          assert_equal Types::Literal.new(:foo), convert(":foo")
          assert_equal Types::Literal.new("bar"), convert('"bar"')
          assert_equal Types::Literal.new(1), convert("1")
          assert_equal Types::Instance.new("Proc"), convert("^(::String) -> void")
          assert_equal(
            Types::HashOf.new(Types::Literal.new(:name), Types::Instance.new("String")),
            convert("{ name: ::String }")
          )
        end

        def test_converts_type_variables
          variable = ::RBS::Types::Variable.new(name: :T, location: nil)

          assert_equal Types::TypeVar.new(:T), converter.convert(variable)
        end

        def test_expands_aliases
          result = convert("::int")

          assert_instance_of Types::Union, result
          assert_includes result.types, Types::Instance.new("Integer")
        end

        def test_maps_interfaces_to_duck_types
          assert_equal Types::Duck.new(["to_s"]), convert("::_ToS")
        end

        def test_degrades_to_unknown_on_failure
          bad_type = Object.new

          assert_equal Types::UNKNOWN, converter.convert(bad_type)
        end
      end
    end
  end
end
