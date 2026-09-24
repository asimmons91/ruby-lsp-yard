# frozen_string_literal: true

require "test_helper"
require "uri"

module RubyLsp
  module Yard
    module Authoring
      class TestSkeleton < Minitest::Test
        include IndexHelpers

        def test_builds_a_comment_with_prefilled_types_from_the_ancestors
          source = <<~RUBY
            module FixtureProject
              class ChildService < BaseService
                def process(input)
                  super
                end
              end
            end
          RUBY
          skeleton = skeleton_for(source, "process", nesting: ["FixtureProject", "ChildService"])

          assert_equal(
            "    # TODO: Add a summary.\n    # @param input [String]\n    # @return [Integer]\n",
            skeleton.text
          )
        end

        def test_falls_back_to_placeholders_without_a_signature
          source = <<~RUBY
            module FixtureProject
              class Documented
                def brand_new(one, two = 1)
                  [one, two]
                end
              end
            end
          RUBY
          skeleton = skeleton_for(source, "brand_new", nesting: ["FixtureProject", "Documented"])

          assert_includes skeleton.text, "# @param one [Type]"
          assert_includes skeleton.text, "# @param two [Type]"
          assert_includes skeleton.text, "# @return [Type]"
        end

        def test_adds_yield_tags_for_yielding_methods
          source = <<~RUBY
            module FixtureProject
              class Documented
                def each_item(list, &block)
                  list.each(&block)
                end
              end
            end
          RUBY
          skeleton = skeleton_for(source, "each_item", nesting: ["FixtureProject", "Documented"])

          assert_includes skeleton.text, "# @yield [args]"
          assert_includes skeleton.text, "# @yieldreturn [Type]"
          assert_includes skeleton.text, "# @param &block [Type]"
        end

        def test_edit_inserts_above_the_definition_with_its_indentation
          source = <<~RUBY
            module FixtureProject
              class ChildService < BaseService
                def process(input)
                  super
                end
              end
            end
          RUBY
          edit = skeleton_for(source, "process", nesting: ["FixtureProject", "ChildService"]).edit

          assert_equal 2, edit.range.start.attributes[:line]
          assert_equal 0, edit.range.start.attributes[:character]
          assert_equal edit.range.start.attributes[:line], edit.range.end.attributes[:line]
          assert_equal edit.range.start.attributes[:character], edit.range.end.attributes[:character]
          assert edit.new_text.start_with?("    # TODO")
          assert edit.new_text.end_with?("\n")
        end

        def test_applying_the_edit_keeps_the_definition_indentation
          source = <<~RUBY
            module FixtureProject
              class ChildService < BaseService
                def process(input)
                  super
                end
              end
            end
          RUBY
          edit = skeleton_for(source, "process", nesting: ["FixtureProject", "ChildService"]).edit
          lines = source.lines.dup
          line = edit.range.start.attributes[:line]
          lines[line] = lines[line].dup.insert(edit.range.start.attributes[:character], edit.new_text)

          assert_equal(<<~RUBY, lines.join)
            module FixtureProject
              class ChildService < BaseService
                # TODO: Add a summary.
                # @param input [String]
                # @return [Integer]
                def process(input)
                  super
                end
              end
            end
          RUBY
        end

        private

        def skeleton_for(source, name, nesting:)
          document = document_for(source)
          def_node = find_def(document, name)
          refute_nil def_node
          Skeleton.new(def_node: def_node, nesting: nesting, document: document, store: store)
        end

        def find_def(document, name)
          stack = [document.ast]
          until stack.empty?
            node = stack.pop
            return node if node.is_a?(Prism::DefNode) && node.name.to_s == name

            node.compact_child_nodes.each { |child| stack << child }
          end
          nil
        end

        def document_for(source)
          RubyLsp::RubyDocument.new(
            source: source,
            version: 1,
            uri: URI("file:///fixture.rb"),
            global_state: RubyLsp::GlobalState.new
          )
        end

        def store
          @store ||= SignatureStore.new(Indexer.wrap(build_fixture_index))
        end
      end
    end
  end
end
