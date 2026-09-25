# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestMacrosLsp < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        def test_completes_macro_generated_methods
          items = complete("FixtureProject::Post.new.\n", "Post.new.")

          title = find_item(items, "title")
          refute_nil title
          assert_equal "String", label_details(title)[:description]

          views = find_item(items, "views")
          refute_nil views
          assert_equal "Integer", label_details(views)[:description]
        end

        def test_completes_macro_generated_attributes_from_an_extended_module
          items = complete("FixtureProject::Tagged.new.\n", "Tagged.new.")

          tag = find_item(items, "tag")
          refute_nil tag
          assert_equal "String", label_details(tag)[:description]

          assert_nil find_item(items, "tag=")
        end

        def test_completes_inherited_macro_generated_methods
          items = complete("FixtureProject::ArchivedPost.new.\n", "ArchivedPost.new.")

          title = find_item(items, "title")
          refute_nil title
          assert_equal "String", label_details(title)[:description]
        end

        def test_completes_singleton_macro_generated_methods
          items = complete("FixtureProject::Widget.\n", "Widget.")

          refute_nil find_item(items, "build_widget")
        end

        def test_singleton_macro_generated_methods_are_not_instance_methods
          items = complete("FixtureProject::Widget.new.\n", "Widget.new.")

          assert_nil find_item(items, "build_widget")
        end

        def test_definition_of_an_inherited_macro_generated_method
          source = <<~RUBY
            post = FixtureProject::ArchivedPost.new
            post.title
          RUBY
          links = nil

          with_server(source) do |server, uri|
            index_fixtures(server)
            links = definition_links(server, uri, source, line_token: "post.title", position_token: "title")
          end

          refute_empty links
          assert_match(/macros\.rb/, links.first.target_uri)
        end

        def test_hover_shows_the_named_macro_expansion
          source = <<~RUBY
            post = FixtureProject::Post.new
            post.duplicate
          RUBY
          text = nil

          with_server(source) do |server, uri|
            index_fixtures(server)
            text = hover_text(server, uri, source, line_token: "post.duplicate", position_token: "duplicate")
          end

          refute_nil text
          assert_includes text, "def duplicate"
          assert_includes text, "self"
        end

        def test_definition_of_a_macro_generated_method_points_at_the_dsl_call
          source = <<~RUBY
            post = FixtureProject::Post.new
            post.title
          RUBY
          links = nil

          with_server(source) do |server, uri|
            index_fixtures(server)
            links = definition_links(server, uri, source, line_token: "post.title", position_token: "title")
          end

          refute_empty links
          assert_match(/macros\.rb/, links.first.target_uri)
        end

        private

        def complete(source, line_token)
          items = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            items = completion_items(server, uri, source, line_token: line_token)
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
