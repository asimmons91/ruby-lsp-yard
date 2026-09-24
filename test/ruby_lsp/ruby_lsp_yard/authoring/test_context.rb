# frozen_string_literal: true

require "test_helper"
require "uri"

module RubyLsp
  module Yard
    module Authoring
      class TestContext < Minitest::Test
        def test_returns_nil_outside_comments
          assert_nil build_context("def foo; end\n", 0, 5)
        end

        def test_detects_a_comment_attached_to_a_definition
          source = <<~RUBY
            module FixtureProject
              class Documented
                # @param name [Str
                def greet(name)
                end
              end
            end
          RUBY

          context = build_context_at_token(source, "[Str")

          assert_equal :type, context.kind
          assert_equal "Str", context.prefix
          assert_equal ["FixtureProject", "Documented"], context.nesting
          assert_equal "FixtureProject::Documented", context.owner_name
          assert_equal Prism::DefNode, context.definition.class
          assert_equal "greet", context.definition_name
          assert context.attached?
          refute context.trailing?
        end

        def test_classifies_a_tag_token
          context = build_context_at_token("# @ret\ndef foo; end\n", "@ret")

          assert_equal :tag, context.kind
          assert_equal "@ret", context.prefix
          assert_equal 2, context.token_range.start.attributes[:character]
        end

        def test_classifies_a_directive_token
          context = build_context_at_token("# @!\ndef foo; end\n", "@!")

          assert_equal :directive, context.kind
          assert_equal "@!", context.prefix
        end

        def test_classifies_a_param_name
          source = "# @param \ndef greet(name); end\n"
          context = build_context(source, 0, source.lines[0].chomp.length)

          assert_equal :param, context.kind
          assert_equal "", context.prefix
          assert_equal "param", context.tag_name
          assert_equal ["name"], context.parameters.map(&:name)
        end

        def test_classifies_free_text
          context = build_context_at_token("# a free text line\ndef foo; end\n", "free")

          assert_equal :free_text, context.kind
        end

        def test_prose_mentions_are_not_tags
          context = build_context_at_token("# ping @user for details\ndef foo; end\n", "@user")

          assert_equal :free_text, context.kind
        end

        def test_skips_destructured_and_anonymous_parameters
          source = <<~RUBY
            # docs
            def process((left, right), *, key:, **, &)
            end
          RUBY
          context = build_context_at_token(source, "docs")

          assert_equal ["key"], context.parameters.map(&:name)
          assert context.yields?
        end

        def test_free_text_is_not_confused_by_prose_after_a_completed_type
          source = "# @param x [String] and some prose\ndef foo(x); end\n"
          context = build_context(source, 0, source.lines[0].chomp.length)

          assert_equal :free_text, context.kind
        end

        def test_collects_the_contiguous_comment_block
          source = <<~RUBY
            # @param name [String] the name
            # @return [Str
            def greet(name)
            end
          RUBY

          context = build_context_at_token(source, "[Str")

          assert_equal ["name"], context.documented_params
          assert_equal ["name"], context.parameters.map(&:name)
        end

        def test_does_not_attach_across_a_blank_line
          source = "# a floating comment\n\ndef foo; end\n"
          context = build_context_at_token(source, "floating")

          refute context.attached?
          assert_nil context.definition
        end

        def test_does_not_attach_trailing_comments
          source = "x = 1 # a trailing comment\ndef foo; end\n"
          context = build_context_at_token(source, "trailing")

          refute context.attached?
        end

        def test_skips_visibility_modifiers_for_the_owner
          source = "# docs here\nprivate def foo; end\n"
          context = build_context_at_token(source, "docs")

          assert_equal "foo", context.definition_name
        end

        def test_detects_parameters_and_yield_and_raise
          source = <<~RUBY
            # docs
            def process(name, limit = 1, *rest, key:, **options, &block)
              yield(name)
              raise KeyError if name.nil?
            end
          RUBY

          context = build_context_at_token(source, "docs")

          assert_equal(
            %i[required optional rest keyword keyword_rest block],
            context.parameters.map(&:kind)
          )
          assert context.yields?
          assert_equal "KeyError", context.raise_class
        end

        def test_does_not_report_yield_without_a_block
          context = build_context_at_token("# docs\ndef foo; end\n", "docs")

          refute context.yields?
          assert_nil context.raise_class
        end

        def test_finds_the_constant_under_the_cursor
          source = "# @param x [FixtureProject::Documented] the doc\ndef foo(x); end\n"
          line = source.lines[0]
          character = line.index("Documented") + 5
          context = build_context(source, 0, character)

          assert_equal "FixtureProject::Documented", context.constant_at_cursor
        end

        def test_nesting_at_returns_the_enclosing_namespaces
          source = <<~RUBY
            module FixtureProject
              class Documented
                def greet; end
              end
            end
          RUBY
          document = build_document(source)
          def_node = document.ast.statements.body.first.body.body.first.body.body.first

          assert_equal ["FixtureProject", "Documented"], Context.nesting_at(document, def_node)
        end

        def test_never_raises_for_non_ruby_documents
          document = Struct.new(:language_id).new(:erb)

          assert_nil Context.build(document, {line: 0, character: 0})
        end

        private

        def build_document(source)
          RubyLsp::RubyDocument.new(
            source: source,
            version: 1,
            uri: URI("file:///fixture.rb"),
            global_state: RubyLsp::GlobalState.new
          )
        end

        def build_context(source, line, character)
          Context.build(build_document(source), {line: line, character: character})
        end

        def build_context_at_token(source, token)
          line = source.lines.index { |candidate| candidate.include?(token) }
          character = source.lines[line].index(token) + token.length
          build_context(source, line, character)
        end
      end
    end
  end
end
