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
      end
    end
  end
end
