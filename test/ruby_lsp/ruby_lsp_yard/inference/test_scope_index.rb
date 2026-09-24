# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/inference"

module RubyLsp
  module Yard
    module Inference
      class TestScopeIndex < Minitest::Test
        include InferenceHelpers

        SOURCE = <<~RUBY
          module FixtureProject
            class Thing
              def work
                x = 1
                x = "two"
                x.to_s
                @value = 1
                @other ||= "fallback"
              end
            end
          end
        RUBY

        def test_reads_the_document_ast_through_the_node_context
          index = scope_index

          assert index.available?
          assert_instance_of Prism::DefNode, index.local_scope
          assert_instance_of Prism::ClassNode, index.class_scope
        end

        def test_is_unavailable_when_the_node_context_shape_changes
          context = context_for(SOURCE, "x.to_s", node_types: [Prism::CallNode])
          context.instance_variable_set(:@nesting_nodes, nil)

          refute ScopeIndex.new(context).available?
        end

        def test_collects_local_assignments_in_source_order_with_offsets
          context = context_for(SOURCE, "x.to_s", node_types: [Prism::CallNode])
          index = ScopeIndex.new(context)
          values = index.assignment_value_nodes("x", SOURCE.length)

          assert_equal ["1", '"two"'], values.map(&:slice)
          assert_equal(
            ["1"],
            index.assignment_value_nodes("x", SOURCE.index('x = "two"')).map(&:slice)
          )
        end

        def test_collects_instance_variable_assignments_from_method_bodies
          context = context_for(SOURCE, "x.to_s", node_types: [Prism::CallNode])
          index = ScopeIndex.new(context)

          assert_equal ["1"], index.ivar_value_nodes("@value").map(&:slice)
          assert_equal ['"fallback"'], index.ivar_value_nodes("@other").map(&:slice)
        end

        def test_blocks_read_assignments_from_the_enclosing_method
          source = <<~RUBY
            def work
              x = 1
              [1].each do
                x.to_s
              end
            end
          RUBY
          context = context_for(source, "x.to_s", node_types: [Prism::CallNode])

          assert_equal ["1"], ScopeIndex.new(context).assignment_value_nodes("x", source.length).map(&:slice)
        end

        def test_lambdas_can_read_enclosing_method_assignments
          source = <<~RUBY
            def work
              x = 1
              -> { x.to_s }
            end
          RUBY
          context = context_for(source, "x.to_s", node_types: [Prism::CallNode])

          assert_equal ["1"], ScopeIndex.new(context).assignment_value_nodes("x", source.length).map(&:slice)
        end

        def test_class_bodies_do_not_read_program_assignments
          source = <<~RUBY
            x = "top level"
            class Thing
              x.to_s
            end
          RUBY
          context = context_for(source, "x.to_s", node_types: [Prism::CallNode])

          assert_empty ScopeIndex.new(context).assignment_value_nodes("x", source.length)
        end

        def test_extracts_block_parameters
          source = <<~RUBY
            Foo.each do |value, *rest, key:, **options, &block|
              value.to_s
            end
          RUBY
          context = context_for(source, "value.to_s", node_types: [Prism::CallNode])

          assert_equal(
            [["value", :required], ["rest", :rest], ["key", :keyword], ["options", :keyword_rest], ["block", :block]],
            ScopeIndex.new(context).block_parameters
          )
        end

        def test_collects_multi_assignments_pairwise
          source = <<~RUBY
            module FixtureProject
              class Thing
                def work
                  a, b = 1, "two"
                  @left, @right = 1, 2
                  first, *middle, last = 1, 2, 3
                  a.to_s
                end
              end
            end
          RUBY
          context = context_for(source, "a.to_s", node_types: [Prism::CallNode])
          index = ScopeIndex.new(context)

          assert_equal ["1"], index.assignment_value_nodes("a", source.length).map(&:slice)
          assert_equal ['"two"'], index.assignment_value_nodes("b", source.length).map(&:slice)
          assert_equal ["1"], index.ivar_value_nodes("@left").map(&:slice)
          assert_equal ["2"], index.ivar_value_nodes("@right").map(&:slice)
          assert_equal ["1"], index.assignment_value_nodes("first", source.length).map(&:slice)
          assert_equal ["3"], index.assignment_value_nodes("last", source.length).map(&:slice)
          assert_empty index.assignment_value_nodes("middle", source.length)
        end

        def test_skips_multi_assignments_without_a_value_split
          source = <<~RUBY
            def work
              a, b = fetch_values
              a.to_s
            end
          RUBY
          context = context_for(source, "a.to_s", node_types: [Prism::CallNode])
          index = ScopeIndex.new(context)

          assert_empty index.assignment_value_nodes("a", source.length)
          assert_empty index.assignment_value_nodes("b", source.length)
        end

        private

        def scope_index
          context = context_for(SOURCE, "x.to_s", node_types: [Prism::CallNode])

          ScopeIndex.new(context)
        end
      end
    end
  end
end
