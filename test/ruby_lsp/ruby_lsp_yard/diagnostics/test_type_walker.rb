# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/diagnostics"

module RubyLsp
  module Yard
    module Diagnostics
      class TestTypeWalker < Minitest::Test
        def test_enumerates_every_type_expression
          raw = Documentation::RawDoc.new(
            params: [Documentation::RawParam.new("n", ["Array<Foo>", "nil"], "")],
            returns: [Documentation::RawReturn.new(["String"], "")],
            yield_params: [Documentation::RawParam.new("v", ["Integer"], "")],
            yield_returns: [Documentation::RawReturn.new(["Symbol"], "")],
            raises: [Documentation::RawRaise.new(["KeyError"], "")],
            options: [Documentation::RawOption.new("opts", :limit, ["Integer"], nil, "")]
          )

          refs = collect(raw)

          assert_equal ["Array<Foo>", "nil", "Integer", "String", "Symbol"], refs.first(5).map(&:text)
          assert_equal ["@param n", "@param n", "@yieldparam v", "@return", "@yieldreturn"], refs.first(5).map(&:tag)
          assert_equal ["@raise", "@option limit"], refs.last(2).map(&:tag)
        end

        def test_enumerates_overload_and_directive_docstrings
          overload = Documentation::RawOverload.new(
            "set(key, value)",
            Documentation::RawDoc.new(params: [Documentation::RawParam.new("key", ["Symbol"], "")])
          )
          directive = Documentation::RawDirective.new(
            kind: :attribute,
            name: "label",
            types: ["rw"],
            doc: Documentation::RawDoc.new(returns: [Documentation::RawReturn.new(["String"], "")])
          )
          raw = Documentation::RawDoc.new(overloads: [overload], directives: [directive])

          refs = collect(raw)

          assert_equal ["Symbol", "String"], refs.map(&:text)
          assert_equal "@overload set(key, value) @param key", refs.first.label
          assert_equal "@!attribute @return", refs.last.label
        end

        def test_attribute_accessor_flags_are_not_types
          directive = Documentation::RawDirective.new(kind: :attribute, name: "label", types: ["rw"], doc: nil)
          raw = Documentation::RawDoc.new(directives: [directive])

          assert_empty collect(raw)
        end

        def test_unresolved_names_skips_type_variables_and_interfaces
          resolver = ->(name, _nesting) { (name == "Array") ? "Array" : nil }
          type = Types::Instance.new(
            "Array",
            [Types::Instance.new("Strng"), Types::Ref.new("T"), Types::Ref.new("_ToS")]
          )

          assert_equal ["Strng"], TypeWalker.unresolved_names(type, resolver: resolver, nesting: [])
        end

        def test_unresolved_names_resolves_relative_names
          resolver = ->(name, nesting) { (nesting == ["Demo"] && name == "Thing") ? "Demo::Thing" : nil }
          type = Types::Instance.new("Thing")

          assert_empty TypeWalker.unresolved_names(type, resolver: resolver, nesting: ["Demo"])
          assert_equal ["Thing"], TypeWalker.unresolved_names(type, resolver: resolver, nesting: [])
        end

        def test_unresolved_names_needs_a_resolver
          assert_empty TypeWalker.unresolved_names(Types::Ref.new("Foo"), resolver: nil, nesting: [])
        end

        def test_compatible_matches_exact_names_and_literals
          assert TypeWalker.compatible?(Types::Instance.new("Integer"), Types::Instance.new("Integer"))
          refute TypeWalker.compatible?(Types::Instance.new("Integer"), Types::Instance.new("String"))
          assert TypeWalker.compatible?(Types::BOOLEAN, Types.literal_class(Types::Literal.new(true)))
          refute TypeWalker.compatible?(Types::Instance.new("Integer"), Types::NIL_TYPE)
          assert TypeWalker.compatible?(Types::Union.new([Types::Instance.new("Integer"), Types::NIL_TYPE]), Types::NIL_TYPE)
        end

        def test_compatible_treats_unknown_duck_and_type_vars_as_unknown
          assert TypeWalker.compatible?(Types::UNKNOWN, Types::Instance.new("String"))
          assert TypeWalker.compatible?(Types::Duck.new(["call"]), Types::Instance.new("String"))
          assert TypeWalker.compatible?(Types::TypeVar.new(:T), Types::Instance.new("String"))
          assert TypeWalker.compatible?(Types::SELF, Types::Instance.new("String"))
          assert TypeWalker.compatible?(Types::VOID, Types::Instance.new("String"))
        end

        def test_compatible_uses_ancestors_for_subclasses
          adapter = Object.new
          def adapter.ancestors(name)
            (name == "Integer") ? ["Integer", "Numeric", "Object"] : []
          end

          declared = Types::Instance.new("Numeric")
          actual = Types::Instance.new("Integer")

          refute TypeWalker.compatible?(declared, actual)
          assert TypeWalker.compatible?(declared, actual, adapter: adapter)
        end

        def test_compatible_checks_declared_literals
          assert TypeWalker.compatible?(Types::Literal.new(:foo), Types::Instance.new("Symbol"))
          refute TypeWalker.compatible?(Types::Literal.new(:foo), Types::Instance.new("String"))
        end

        private

        def collect(raw)
          refs = []
          TypeWalker.each_type_string(raw) { |ref| refs << ref }
          refs
        end
      end
    end
  end
end
