# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/documentation"

module RubyLsp
  module Yard
    module Documentation
      class TestTagExtractor < Minitest::Test
        def extract(comment)
          TagExtractor.new.extract(comment)
        end

        def test_parses_summary_and_params
          doc = extract(<<~DOC)
            Fetches the thing.

            More prose.
            @param key [Symbol] the key
            @param default [String, nil] fallback value
          DOC

          assert_equal "Fetches the thing.\n\nMore prose.", doc.summary
          assert_equal ["key", "default"], doc.params.map(&:name)
          assert_equal [["Symbol"], ["String", "nil"]], doc.params.map(&:types)
          assert_equal ["the key", "fallback value"], doc.params.map(&:text)
        end

        def test_parses_params_with_sigils_and_keywords
          doc = extract(<<~DOC)
            @param *args [String]
            @param **opts [Hash]
            @param &block [Proc]
            @param key: [Symbol]
          DOC

          assert_equal ["*args", "**opts", "&block", "key:"], doc.params.map(&:name)
        end

        def test_parses_returns
          doc = extract(<<~DOC)
            @return [String] when found
            @return [nil] otherwise
          DOC

          assert_equal [["String"], ["nil"]], doc.returns.map(&:types)
          assert_equal ["when found", "otherwise"], doc.returns.map(&:text)
          assert_equal ["String", "nil"], doc.return_types
        end

        def test_parses_yield_tags
          doc = extract(<<~DOC)
            @yield [a, b] yields values
            @yieldparam a [String] first
            @yieldparam b [Integer] second
            @yieldreturn [Boolean] accept?
          DOC

          assert_equal [["a", "b"]], doc.yields.map(&:names)
          assert_equal ["a", "b"], doc.yield_params.map(&:name)
          assert_equal [["String"], ["Integer"]], doc.yield_params.map(&:types)
          assert_equal [["Boolean"]], doc.yield_returns.map(&:types)
        end

        def test_parses_options
          doc = extract("@option opts [String] :subject ('none') the subject")
          option = doc.options.first

          assert_equal "opts", option.name
          assert_equal ":subject", option.key
          assert_equal ["String"], option.types
          assert_equal ["'none'"], option.default
          assert_equal "the subject", option.text
        end

        def test_parses_raises
          doc = extract("@raise [ArgumentError, TypeError] when invalid")

          assert_equal [["ArgumentError", "TypeError"]], doc.raises.map(&:types)
          assert_equal ["when invalid"], doc.raises.map(&:text)
        end

        def test_parses_deprecated
          doc = extract("@deprecated Use {#bar} instead")

          assert doc.deprecated?
          assert_equal "Use {#bar} instead", doc.deprecated
        end

        def test_parses_overloads_with_nested_tags
          doc = extract(<<~DOC)
            @overload set(key, value)
              Sets a value on key.
              @param key [Symbol] the key
              @param value [Object] the value
              @return [self]
            @overload set(value)
              Sets a value on the default key.
              @param value [Object] the value
          DOC

          assert_equal 2, doc.overloads.size
          first = doc.overloads.first
          assert_equal "set(key, value)", first.signature
          assert_equal ["key", "value"], first.doc.params.map(&:name)
          assert_equal [["self"]], first.doc.returns.map(&:types)
          assert_equal 1, doc.overloads.last.doc.params.size
        end

        def test_parses_metadata_tags
          doc = extract(<<~DOC)
            @api private
            @note keep calm
            @see Foo#bar
            @since 1.2.3
            @example Reverse
              "abc".reverse
          DOC

          assert_equal %w[api note see since example], doc.metadata.map(&:tag)
          assert_equal "Foo#bar", doc.metadata[2].name
          assert_equal "Reverse", doc.metadata[4].name
        end

        def test_parses_leading_see_reference
          doc = extract(<<~DOC)
            (see FixtureProject::Animal#speak)
            @param suffix [String]
          DOC

          assert_equal "FixtureProject::Animal#speak", doc.reference
          assert_equal ["suffix"], doc.params.map(&:name)
        end

        def test_parses_method_directive
          doc = extract(<<~DOC)
            @!method self.create(name)
              @param name [String] the name
              @return [Object]
          DOC

          directive = doc.directives.first
          assert_equal :method, directive.kind
          assert_equal "create", directive.name
          assert directive.singleton
          assert_equal ["name"], directive.doc.params.map(&:name)
        end

        def test_parses_instance_method_directive
          doc = extract("@!method build(id)")

          directive = doc.directives.first
          assert_equal :method, directive.kind
          assert_equal "build", directive.name
          refute directive.singleton
        end

        def test_parses_attribute_directive
          doc = extract(<<~DOC)
            @!attribute [rw] age
              @return [Integer]
          DOC

          directive = doc.directives.first
          assert_equal :attribute, directive.kind
          assert_equal "age", directive.name
          assert_equal ["rw"], directive.types
          assert_equal [["Integer"]], directive.doc.returns.map(&:types)
        end

        def test_parses_parse_directive
          doc = extract(<<~DOC)
            @!parse
              def generated(value)
              end
          DOC

          directive = doc.directives.first
          assert_equal :parse, directive.kind
          assert_includes directive.text, "def generated(value)"
        end

        def test_parses_parse_directive_with_inline_code
          doc = extract("@!parse attr_reader :generated")

          assert_equal :parse, doc.directives.first.kind
          assert_equal "attr_reader :generated", doc.directives.first.text
        end

        def test_parses_visibility_directive
          doc = extract("@!visibility private")

          directive = doc.directives.first
          assert_equal :visibility, directive.kind
          assert_equal "private", directive.text
        end

        def test_unknown_tags_are_ignored
          doc = extract("@param [String] loose_name\n@totally_unknown value")

          assert_equal ["loose_name"], doc.params.map(&:name)
          assert_equal [["String"]], doc.params.map(&:types)
          assert_empty doc.metadata
        end

        def test_malformed_input_never_raises
          [
            nil,
            "",
            "@param",
            "@param [",
            "@return [Array<",
            "@overload (((",
            "@!method",
            "@option",
            "@!attribute",
            "\u0000invalid"
          ].each do |comment|
            doc = extract(comment)
            assert_instance_of RawDoc, doc
          end
        end

        def test_empty_doc
          assert extract("").empty?
          assert extract("Just prose").summary == "Just prose"
        end
      end
    end
  end
end
