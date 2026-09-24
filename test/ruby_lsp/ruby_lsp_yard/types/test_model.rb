# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/types"

module RubyLsp
  module Yard
    module Types
      class TestModel < Minitest::Test
        def test_substitutes_type_vars_into_instances_and_singletons
          mapping = {E: Instance.new("String")}

          assert_equal Instance.new("Array", [Instance.new("String")]),
            Types.substitute_type_vars(Instance.new("Array", [TypeVar.new(:E)]), mapping)
          assert_equal Singleton.new("Array", [TypeVar.new(:T)]),
            Types.substitute_type_vars(Singleton.new("Array", [TypeVar.new(:T)]), mapping)
        end

        def test_leaves_unbound_type_vars_alone
          assert_equal TypeVar.new(:E), Types.substitute_type_vars(TypeVar.new(:E), {})
          assert_equal TypeVar.new(:T), Types.substitute_type_vars(TypeVar.new(:T), {E: Instance.new("String")})
        end

        def test_substitutes_into_unions_tuples_and_hashes
          mapping = {E: Instance.new("String")}

          assert_equal(
            Types.union([Instance.new("String"), Instance.new("Integer")]),
            Types.substitute_type_vars(Union.new([TypeVar.new(:E), Instance.new("Integer")]), mapping)
          )
          assert_equal(
            Tuple.new([Instance.new("String"), Instance.new("String")]),
            Types.substitute_type_vars(Tuple.new([TypeVar.new(:E), TypeVar.new(:E)]), mapping)
          )
          assert_equal(
            HashOf.new(Instance.new("String"), Instance.new("String")),
            Types.substitute_type_vars(HashOf.new(TypeVar.new(:E), TypeVar.new(:E)), mapping)
          )
        end
      end
    end
  end
end
