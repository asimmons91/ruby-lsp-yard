# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/rbs"

module RubyLsp
  module Yard
    module Rbs
      class TestLoader < Minitest::Test
        def test_loads_core_and_stdlib_synchronously
          loader = Loader.new(background: false)
          loader.start

          assert loader.ready?
          refute_nil loader.environment
          refute_nil loader.builder
          assert loader.environment.class_decls.key?(::RBS::TypeName.parse("::String"))
          assert loader.environment.class_decls.key?(::RBS::TypeName.parse("::Pathname"))
        end

        def test_loads_in_the_background
          loader = Loader.new
          loader.start

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
          sleep(0.01) until loader.ready? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          assert loader.ready?
        ensure
          loader&.cancel
        end

        def test_skips_libraries_that_do_not_exist
          loader = Loader.new(background: false)
          loader.stub(:each_library, ["definitely-not-an-rbs-library"]) do
            loader.start
          end

          assert loader.ready?
          assert loader.environment.class_decls.key?(::RBS::TypeName.parse("::String"))
        end

        def test_cancel_does_not_publish_a_half_built_environment
          loader = Loader.new
          loader.cancel
          loader.load

          refute loader.ready?
        end

        def test_loads_an_rbs_collection_from_the_workspace
          loader = Loader.new(background: false, workspace_path: collection_path)
          loader.start

          assert loader.ready?
          assert loader.environment.class_decls.key?(::RBS::TypeName.parse("::FixtureCollectionGem"))
          assert loader.environment.class_decls.key?(::RBS::TypeName.parse("::FixtureProject::Animal"))
        end

        def test_ignores_a_missing_collection
          loader = Loader.new(background: false, workspace_path: File.expand_path("../../..", __dir__))
          loader.start

          assert loader.ready?
          refute loader.environment.class_decls.key?(::RBS::TypeName.parse("::FixtureCollectionGem"))
        end

        private

        def collection_path
          File.expand_path("../../../fixtures/rbs_collection", __dir__)
        end
      end
    end
  end
end
