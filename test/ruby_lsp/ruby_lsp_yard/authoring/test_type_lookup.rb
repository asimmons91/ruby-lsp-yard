# frozen_string_literal: true

require "test_helper"
require "uri"

module RubyLsp
  module Yard
    module Authoring
      class TestTypeLookup < Minitest::Test
        include IndexHelpers

        def test_hover_shows_the_class_documentation
          lookup = lookup_for("# @param x [FixtureProject::Animal]\ndef take(x); end\n")

          markdown = lookup.hover_markdown

          refute_nil markdown
          assert_includes markdown, "class FixtureProject::Animal"
          assert_includes markdown, "@!method self.build"
        end

        def test_hover_uses_the_module_keyword
          lookup = lookup_for("# @param x [FixtureProject::Greetable]\ndef take(x); end\n")

          assert_includes lookup.hover_markdown, "module FixtureProject::Greetable"
        end

        def test_hover_is_nil_for_unresolvable_names
          lookup = lookup_for("# @param x [NoSuchThing]\ndef take(x); end\n")

          assert_nil lookup.hover_markdown
        end

        def test_links_point_at_the_constant_definition
          lookup = lookup_for("# @param x [FixtureProject::Animal]\ndef take(x); end\n")

          links = lookup.links

          refute_empty links
          link = links.first
          assert_match(/animals\.rb/, link.target_uri)
        end

        def test_links_are_empty_for_unresolvable_names
          lookup = lookup_for("# @param x [NoSuchThing]\ndef take(x); end\n")

          assert_empty lookup.links
        end

        def test_does_nothing_when_the_cursor_is_not_on_a_constant
          lookup = lookup_for("# some words here\ndef take(x); end\n")

          assert_nil lookup.resolved
          assert_nil lookup.hover_markdown
        end

        private

        def lookup_for(source)
          line = source.lines.index { |candidate| candidate.include?("#") }
          text = source.lines[line]
          character = text.include?("[") ? text.index("[") + 3 : text.chomp.length
          context = Context.build(
            document_for(source),
            {line: line, character: character},
            adapter: adapter
          )
          refute_nil context
          TypeLookup.new(context, adapter: adapter)
        end

        def document_for(source)
          RubyLsp::RubyDocument.new(
            source: source,
            version: 1,
            uri: URI("file:///fixture.rb"),
            global_state: RubyLsp::GlobalState.new
          )
        end

        def adapter
          @adapter ||= Indexer.wrap(build_fixture_index)
        end
      end
    end
  end
end
