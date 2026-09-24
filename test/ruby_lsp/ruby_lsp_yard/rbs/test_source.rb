# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/rbs"

module RubyLsp
  module Yard
    module Rbs
      class TestSource < Minitest::Test
        class << self
          def loader
            @loader ||= begin
              loader = Loader.new(background: false)
              loader.start
              loader
            end
          end
        end

        def source
          @source ||= Source.new(self.class.loader)
        end

        def test_reports_readiness_of_the_environment
          assert source.ready?
        end

        def test_returns_nil_for_workspace_owners
          assert_nil source.lookup("FixtureProject::Documented", "fetch")
          assert_nil source.lookup("Nothing", "call")
        end

        def test_looks_up_instance_methods_with_overloads
          signature = source.lookup("String", "split")

          refute_nil signature
          assert_equal "String", signature.owner
          assert_equal :public, signature.visibility
          assert_equal Types::Instance.new("Array", [Types::Instance.new("String")]), signature.return_types
          assert_equal 2, signature.overloads.size
        end

        def test_exposes_class_type_params_and_type_variables
          signature = source.lookup("Array", "first")

          assert_equal [:E], signature.type_params
          assert_equal Types::TypeVar.new(:E), signature.return_types
        end

        def test_exposes_method_type_params
          signature = source.lookup("Array", "map")

          assert_equal [:T], signature.method_type_params
          assert_equal Types::Instance.new("Array", [Types::TypeVar.new(:T)]), signature.return_types
        end

        def test_block_signatures_become_yield_params
          signature = source.lookup("Hash", "each")

          param = signature.yield_params.first
          refute_nil param
          assert_equal Types::Tuple.new([Types::TypeVar.new(:K), Types::TypeVar.new(:V)]), param.types
        end

        def test_maps_rbs_visibility
          assert_equal :private, source.lookup("Kernel", "puts").visibility
        end

        def test_marks_signatures_as_rbs_sourced
          signature = source.lookup("String", "split")

          refute_nil signature
          assert_equal :rbs, signature.source
          refute signature.yard?
          refute signature.overloads.first.yard?
        end

        def test_looks_up_singleton_methods
          signature = source.lookup("String", "new", singleton: true)

          refute_nil signature
          assert signature.singleton
        end

        def test_normalizes_singleton_owner_names
          signature = source.lookup("String::<Class:String>", "new", singleton: true)

          refute_nil signature
          assert_equal "String", signature.owner
        end

        def test_returns_nil_for_unknown_methods
          assert_nil source.lookup("String", "definitely_not_a_method")
        end

        def test_degrades_to_nil_when_not_ready
          not_ready = Source.new(Loader.new)

          assert_nil not_ready.lookup("String", "split")
        end
      end
    end
  end
end
