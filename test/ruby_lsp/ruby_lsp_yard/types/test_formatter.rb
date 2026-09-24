# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/types"

module RubyLsp
  module Yard
    module Types
      class TestFormatter < Minitest::Test
        def render(type)
          Formatter.format(type)
        end

        def test_formats_simple_and_generic_instances
          assert_equal "String", render(Instance.new("String"))
          assert_equal "Array<String>", render(Instance.new("Array", [Instance.new("String")]))
          assert_equal "Hash{K => V}", render(HashOf.new(Instance.new("K"), Instance.new("V")))
        end

        def test_formats_nilable_unions_with_a_question_mark
          assert_equal "String?", render(Union.new([Instance.new("String"), NIL_TYPE]))
          assert_equal "nil", render(Union.new([NIL_TYPE]))
          assert_equal "String | Integer", render(Union.new([Instance.new("String"), Instance.new("Integer")]))
          assert_equal "String | Integer | nil",
            render(Union.new([Instance.new("String"), Instance.new("Integer"), NIL_TYPE]))
        end

        def test_formats_type_variables
          assert_equal "E", render(TypeVar.new(:E))
          assert_equal "Array<E>", render(Instance.new("Array", [TypeVar.new(:E)]))
        end

        def test_formats_specials_and_literals
          assert_equal "Boolean", render(BOOLEAN)
          assert_equal "self", render(SELF)
          assert_equal "void", render(VOID)
          assert_equal "untyped", render(UNTYPED)
          assert_equal "untyped", render(UNKNOWN)
          assert_equal ":foo", render(Literal.new(:foo))
          assert_equal '"bar"', render(Literal.new("bar"))
          assert_equal "1", render(Literal.new(1))
        end

        def test_formats_tuples_ducks_singletons_and_refs
          assert_equal "(String, Integer)", render(Tuple.new([Instance.new("String"), Instance.new("Integer")]))
          assert_equal "#read, #close", render(Duck.new(["read", "close"]))
          assert_equal "Class<Foo>", render(Singleton.new("Foo"))
          assert_equal "Missing::Thing", render(Ref.new("Missing::Thing"))
        end
      end
    end
  end
end
