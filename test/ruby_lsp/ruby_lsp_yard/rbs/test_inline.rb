# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/rbs"

module RubyLsp
  module Yard
    module Rbs
      class TestInline < Minitest::Test
        include IndexHelpers

        OWNER = "FixtureProject::InlineThing"

        def setup
          @adapter = Indexer.wrap(build_fixture_index)
          @inline = Inline.new(@adapter)
          @uri = fixture_uri("project/lib/inline.rb")
        end

        def test_reads_method_annotations
          repeat = @inline.lookup(@uri, OWNER, "repeat")

          refute_nil repeat
          assert_equal :rbs, repeat.source
          assert_equal Types::Instance.new("String"), repeat.return_types
          assert_equal [:times], repeat.params.map(&:name)
          assert_equal [Types::Instance.new("Integer")], repeat.params.map(&:types)
        end

        def test_reads_short_annotations_and_keywords
          assert_equal Types::Instance.new("Integer"), @inline.lookup(@uri, OWNER, "count").return_types

          configure = @inline.lookup(@uri, OWNER, "configure")

          refute_nil configure
          assert_equal [:visible], configure.params.map(&:name)
          assert_equal [Types::BOOLEAN], configure.params.map(&:types)
        end

        def test_reads_attribute_annotations
          label = @inline.lookup(@uri, OWNER, "label")

          refute_nil label
          assert_equal :attribute, label.kind
          assert_equal Types::Instance.new("String"), label.return_types
        end

        def test_skips_files_without_the_magic_comment
          assert_nil @inline.lookup(fixture_uri("project/lib/animals.rb"), "FixtureProject::Animal", "speak")
        end

        def test_singleton_and_unknown_lookups_return_nil
          assert_nil @inline.lookup(@uri, OWNER, "count", singleton: true)
          assert_nil @inline.lookup(@uri, OWNER, "missing")
        end

        def test_resolves_core_aliases_and_interfaces_when_a_loader_is_available
          loader = Rbs::Loader.new(background: false)
          loader.start
          inline = Inline.new(@adapter, loader: loader)

          amount = inline.lookup(@uri, OWNER, "amount")
          refute_nil amount
          expected = Types.union([
            Types::Instance.new("Integer"),
            Types::Instance.new("Float"),
            Types::Instance.new("Rational")
          ])
          assert_equal expected, amount.return_types

          textual = inline.lookup(@uri, OWNER, "textual")
          refute_nil textual
          assert_equal Types::Duck.new(["to_s"]), textual.return_types
        end

        def test_degrades_alias_and_interface_types_without_a_loader
          amount = @inline.lookup(@uri, OWNER, "amount")

          refute_nil amount
          assert_equal Types::UNKNOWN, amount.return_types

          textual = @inline.lookup(@uri, OWNER, "textual")
          refute_nil textual
          assert_equal Types::UNKNOWN, textual.return_types
        end

        def test_rebuilds_cached_files_when_the_environment_becomes_ready
          loader = Rbs::Loader.new(background: false)
          inline = Inline.new(@adapter, loader: loader)

          assert_equal Types::UNKNOWN, inline.lookup(@uri, OWNER, "amount").return_types

          loader.start

          expected = Types.union([
            Types::Instance.new("Integer"),
            Types::Instance.new("Float"),
            Types::Instance.new("Rational")
          ])
          assert_equal expected, inline.lookup(@uri, OWNER, "amount").return_types
        end
      end
    end
  end
end
