# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/signature"

module RubyLsp
  module Yard
    class TestSignature < Minitest::Test
      def test_parameter_list_renders_types_and_kinds
        signature = Signature.new(
          name: :fetch,
          params: [
            Signature::Param.new(name: :key, kind: :required, types: Types::Instance.new("Symbol")),
            Signature::Param.new(
              name: :default,
              kind: :optional,
              types: Types::Union.new([Types::Instance.new("String"), Types::NIL_TYPE])
            ),
            Signature::Param.new(name: :options, kind: :keyword_rest, types: Types::UNKNOWN)
          ]
        )

        assert_equal "(key: Symbol, default = ...: String?, **options)", signature.parameter_list
      end

      def test_parameter_list_falls_back_to_the_first_overload
        overload = Signature.new(
          name: :find,
          params: [
            Signature::Param.new(name: :key, kind: :required, types: Types::Instance.new("Symbol"))
          ]
        )
        signature = Signature.new(name: :find, overloads: [overload])

        assert_equal "(key: Symbol)", signature.parameter_list
        assert_equal "()", Signature.new(name: :find).parameter_list
      end

      def test_return_type_string
        typed = Signature.new(name: :a, return_types: Types::Instance.new("String"))
        unknown = Signature.new(name: :a)

        assert_equal "String", typed.return_type_string
        assert_nil unknown.return_type_string
      end
    end
  end
end
