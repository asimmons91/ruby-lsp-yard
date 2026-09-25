# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/documentation"

module RubyLsp
  module Yard
    module Documentation
      class TestSupport < Minitest::Test
        def test_load_is_idempotent
          Support.load!

          assert Support.loaded?
          assert_instance_of StringIO, ::YARD::Logger.instance.io
        end

        def test_yard_does_not_log_to_stdout
          out, err = capture_io do
            TagExtractor.new.extract("An unknown tag @nonsense is ignored")
          end

          assert_empty out
          assert_empty err
        end

        def test_parse_directives_do_not_execute_the_source_parser
          doc = TagExtractor.new.extract(<<~DOC)
            @!parse
              def dynamically_generated
              end
          DOC

          assert_equal 1, doc.directives.size
          assert_equal :parse, doc.directives.first.kind
          assert_empty ::YARD::Registry.all
        end

        def test_macro_directives_do_not_execute
          doc = TagExtractor.new.extract(<<~DOC)
            @!macro [new] returnself
              @return [self]
          DOC

          assert_equal 1, doc.directives.size
          assert_equal :macro, doc.directives.first.kind
          assert_equal "returnself", doc.directives.first.name
          assert_empty ::YARD::Registry.all
        end
      end
    end
  end
end
