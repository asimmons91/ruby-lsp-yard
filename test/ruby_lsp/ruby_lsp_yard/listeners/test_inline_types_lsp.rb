# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestInlineTypesLsp < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        def test_type_annotation_overrides_local_inference
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  # @type [FixtureProject::Documented]
                  doc = unknown_builder
                  doc.fe
                end
              end
            end
          RUBY

          items = complete(source, "doc.fe")

          fetch = find_item(items, "fetch")
          refute_nil fetch
          assert_includes label_details(fetch)[:detail], "key: Symbol"
        end

        def test_type_annotation_overrides_instance_variable_inference
          source = <<~RUBY
            module FixtureProject
              class Thing
                def setup
                  # @type [FixtureProject::Documented]
                  @thing = unknown_builder
                end

                def use
                  @thing.fe
                end
              end
            end
          RUBY

          items = complete(source, "@thing.fe", position_token: "fe")

          refute_nil find_item(items, "fetch")
        end

        def test_union_annotations_keep_every_member
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  # @type [FixtureProject::Documented, String]
                  doc = unknown_builder
                  doc.fe
                end
              end
            end
          RUBY

          items = complete(source, "doc.fe")

          refute_nil find_item(items, "fetch")
        end

        def test_unknown_receivers_without_annotations_emit_nothing
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  doc = unknown_builder
                  doc.fe
                end
              end
            end
          RUBY

          assert_empty complete(source, "doc.fe")
        end

        def test_solargraph_config_domains_apply_workspace_wide
          Dir.mktmpdir do |dir|
            File.write(File.join(dir, ".solargraph.yml"), "domains:\n  - FixtureProject::DslHelpers\n")

            Dir.chdir(dir) do
              items = complete(PLAIN_SOURCE, "dsl_")

              refute_nil find_item(items, "dsl_greet")
            end
          end
        end

        def test_rbs_inline_annotations_type_completion
          items = complete("FixtureProject::InlineThing.new.\n", "InlineThing.new.")

          repeat = find_item(items, "repeat")
          refute_nil repeat
          assert_equal "String", label_details(repeat)[:description]
        end

        def test_rbs_inline_wins_over_yard_on_hover
          source = "FixtureProject::InlineThing.new.typed\n"
          text = nil

          with_server(source) do |server, uri|
            index_fixtures(server)
            text = hover_text(server, uri, source, line_token: "typed", position_token: "typed")
          end

          refute_nil text
          assert_includes text, "def typed() → Symbol"
        end

        PLAIN_SOURCE = <<~RUBY
          module FixtureProject
            class PlainHost
              def use
                dsl_
              end
            end
          end
        RUBY

        private

        def complete(source, line_token, position_token: nil)
          items = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            items = completion_items(server, uri, source, line_token: line_token, position_token: position_token)
          end

          items
        end

        def find_item(items, label)
          items.find { |item| item.label == label }
        end
      end
    end
  end
end
