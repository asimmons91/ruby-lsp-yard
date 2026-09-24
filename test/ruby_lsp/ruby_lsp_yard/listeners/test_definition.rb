# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestDefinition < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        def test_finds_the_definition_for_a_typed_local_receiver
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  doc = FixtureProject::Documented.new
                  doc.fetch(:key)
                end
              end
            end
          RUBY

          links = definition(source, "doc.fetch", position_token: "fetch")

          assert_equal 1, links.size
          assert_includes links.first.target_uri, "documented.rb"
        end

        def test_finds_inherited_method_definitions
          source = "FixtureProject::Dog.new.speak\n"

          links = definition(source, "speak")

          assert_equal 1, links.size
          assert_includes links.first.target_uri, "animals.rb"
        end

        def test_finds_singleton_method_definitions
          source = "FixtureProject::Dog.species\n"

          links = definition(source, "species")

          assert_equal 1, links.size
          assert_includes links.first.target_uri, "animals.rb"
        end

        def test_follows_return_types_through_chains
          source = "FixtureProject::Documented.new.chain.label\n"

          links = definition(source, "chain.label", position_token: "label")

          assert_equal 1, links.size
          assert_includes links.first.target_uri, "documented.rb"
        end

        def test_uses_param_types_and_narrows_the_host_fallback
          source = <<~RUBY
            module FixtureProject
              class Documented
                def label_of(item)
                  item.label
                end
              end
            end
          RUBY

          links = definition(source, "item.label", position_token: "label")

          assert_equal 1, links.size
          assert_includes links.first.target_uri, "inference.rb"
        end

        def test_finds_definitions_for_every_union_member
          source = "FixtureProject::Inferable.new.ambiguous.label\n"

          links = definition(source, "ambiguous.label", position_token: "label")

          assert_equal 2, links.size
          assert_equal links.map { |link| File.basename(link.target_uri) }.sort,
            ["documented.rb", "inference.rb"]
        end

        def test_leaves_the_host_fallback_for_unknown_receivers
          source = "mystery.label\n"

          links = definition(source, "mystery.label", position_token: "label")

          assert_equal 2, links.size
        end

        def test_is_disabled_by_settings
          source = <<~RUBY
            module FixtureProject
              class Documented
                def label_of(item)
                  item.label
                end
              end
            end
          RUBY

          links = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            override_addon_settings(enableDefinition: false)
            links = definition_links(server, uri, source, line_token: "item.label", position_token: "label")
          end

          assert_equal 2, links.size
        end

        private

        def definition(source, line_token, position_token: nil)
          links = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            links = definition_links(server, uri, source, line_token: line_token, position_token: position_token)
          end

          links
        end
      end
    end
  end
end
