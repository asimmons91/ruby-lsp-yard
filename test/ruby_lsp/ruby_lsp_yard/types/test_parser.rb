# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/types"

module RubyLsp
  module Yard
    module Types
      class TestParser < Minitest::Test
        def parser(nesting: [])
          Parser.new(resolver: method(:resolve), nesting: nesting)
        end

        # Resolves any capitalised name to a prefixed version, so tests can tell resolved and unresolved names apart.
        def resolve(name, _nesting)
          return nil if name.start_with?("Missing", "Nope")
          return nil unless name.match?(/\A[:\w]*[A-Z]/)

          "Resolved::#{name.delete_prefix("::")}"
        end

        def test_parses_a_simple_class_name
          assert_equal Instance.new("Resolved::String"), parser.parse("String")
        end

        def test_unresolved_names_stay_refs
          assert_equal Ref.new("Missing"), parser.parse("Missing")
          assert_nil resolve("missing", [])
        end

        def test_resolution_uses_the_given_nesting
          resolver = ->(name, nesting) { nesting.include?("FixtureProject") ? "FixtureProject::Dog" : nil }

          assert_equal Instance.new("FixtureProject::Dog"), Parser.new(resolver: resolver, nesting: ["FixtureProject"]).parse("Dog")
        end

        def test_parses_unions_and_drops_unknowns
          assert_equal Union.new([Instance.new("Resolved::String"), NIL_TYPE]), parser.parse("String, nil")
        end

        def test_parse_list_builds_a_union
          assert_equal Union.new([Instance.new("Resolved::String"), NIL_TYPE]), parser.parse_list(["String", "nil"])
        end

        def test_single_member_union_collapses
          assert_equal Instance.new("Resolved::String"), parser.parse_list(["String"])
        end

        def test_parses_generics
          assert_equal Instance.new("Resolved::Array", [Instance.new("Resolved::String")]), parser.parse("Array<String>")
          assert_equal(
            Instance.new("Resolved::Enumerable", [Instance.new("Resolved::Array", [Instance.new("Resolved::String")])]),
            parser.parse("Enumerable<Array<String>>")
          )
        end

        def test_parses_hashes_in_both_notations
          expected = HashOf.new(Instance.new("Resolved::Symbol"), Instance.new("Resolved::Integer"))

          assert_equal expected, parser.parse("Hash{Symbol => Integer}")
          assert_equal expected, parser.parse("Hash<Symbol, Integer>")
        end

        def test_parses_hash_without_hash_prefix
          expected = HashOf.new(Instance.new("Resolved::Symbol"), Instance.new("Resolved::Integer"))

          assert_equal expected, parser.parse("{Symbol => Integer}")
        end

        def test_parses_tuples
          assert_equal Tuple.new([Instance.new("Resolved::String"), Instance.new("Resolved::Integer")]),
            parser.parse("(String, Integer)")
          assert_equal Tuple.new([Instance.new("Resolved::String"), Instance.new("Resolved::Integer")]),
            parser.parse("Array(String, Integer)")
        end

        def test_parses_nested_tuple_in_generic
          assert_equal Instance.new("Resolved::Array", [Tuple.new([Instance.new("Resolved::String")])]),
            parser.parse("Array<(String)>")
        end

        def test_maps_class_to_singleton
          assert_equal Singleton.new("Resolved::Foo"), parser.parse("Class<Foo>")
        end

        def test_parses_duck_types
          assert_equal Duck.new(["read"]), parser.parse("#read")
          assert_equal Duck.new(["read", "close"]), parser.parse_list(["#read", "#close"])
          assert_equal Duck.new(["empty?"]), parser.parse("#empty?")
        end

        def test_parses_pipe_unions_duck_signatures_and_brackets
          assert_equal Union.new([Instance.new("Resolved::Corrector"), NIL_TYPE]), parser.parse("Corrector | nil")
          assert_equal Duck.new(["call"]), parser.parse("#call(Diagnostic)")
          assert_equal Duck.new(["write"]), parser.parse("#write() ")
          assert_equal Tuple.new([Instance.new("Resolved::Integer"), Instance.new("Resolved::Integer")]),
            parser.parse("[Integer, Integer]")
          assert_equal Instance.new("Resolved::Array", [Union.new([Instance.new("Resolved::Action"), NIL_TYPE])]),
            parser.parse("Array(Action | nil)")
        end

        def test_parses_literals
          assert_equal Literal.new(:foo), parser.parse(":foo")
          assert_equal Literal.new("bar"), parser.parse('"bar"')
          assert_equal Literal.new("bar"), parser.parse("'bar'")
          assert_equal Literal.new(1), parser.parse("1")
          assert_equal Literal.new(1.5), parser.parse("1.5")
          assert_equal Literal.new(-3), parser.parse("-3")
        end

        def test_maps_special_names
          assert_equal NIL_TYPE, parser.parse("nil")
          assert_equal BOOLEAN, parser.parse("Boolean")
          assert_equal BOOLEAN, parser.parse("true")
          assert_equal BOOLEAN, parser.parse("false")
          assert_equal SELF, parser.parse("self")
          assert_equal VOID, parser.parse("void")
          assert_equal UNTYPED, parser.parse("undefined")
          assert_equal UNTYPED, parser.parse("untyped")
          assert_equal UNKNOWN, parser.parse("Object")
        end

        def test_tolerates_whitespace
          assert_equal(
            HashOf.new(Instance.new("Resolved::String"), Instance.new("Resolved::Symbol")),
            parser.parse("  Hash{ String  =>  Symbol }  ")
          )
          assert_equal Instance.new("Resolved::Array", [Instance.new("Resolved::Hash")]), parser.parse("Array< Hash >")
        end

        def test_leading_colons_are_preserved_for_resolution
          assert_equal Instance.new("Resolved::Foo"), parser.parse("::Foo")
        end

        def test_malformed_input_returns_unknown
          [
            "",
            "Array<",
            "Hash{",
            "#",
            "@",
            "{String}",
            "String =>",
            '"unterminated',
            "Array<String",
            "Foo<Bar"
          ].each do |type|
            assert_equal UNKNOWN, parser.parse(type), "expected #{type.inspect} to parse to Unknown"
          end
        end

        def test_parse_bang_reports_failures
          assert_raises(ParseError) { parser.parse!("Array<") }
          assert_equal Instance.new("Resolved::String"), parser.parse!("String")
        end

        def test_union_helpers
          assert_equal UNKNOWN, Types.union([UNKNOWN, UNKNOWN])
          assert_equal UNKNOWN, Types.union([])
          assert_equal Instance.new("Resolved::String"), Types.union([UNKNOWN, Instance.new("Resolved::String")])
          assert_equal Instance.new("Resolved::String"), Types.union([Instance.new("Resolved::String"), Instance.new("Resolved::String")])
          assert_equal Duck.new(["a", "b"]), Types.union([Duck.new(["a"]), Duck.new(["b"])])
          assert Types.unknown?(UNKNOWN)
          refute Types.unknown?(NIL_TYPE)
          assert Types.nil_type?(NIL_TYPE)
          refute Types.nil_type?(BOOLEAN)
        end

        def test_literal_class
          assert_equal Instance.new("String"), Types.literal_class(Literal.new("x"))
          assert_equal Instance.new("Symbol"), Types.literal_class(Literal.new(:x))
          assert_equal BOOLEAN, Types.literal_class(Literal.new(true))
          assert_equal UNKNOWN, Types.literal_class(Instance.new("String"))
        end
      end
    end
  end
end
