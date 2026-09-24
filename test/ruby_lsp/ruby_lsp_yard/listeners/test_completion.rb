# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestCompletion < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        LOCAL_SOURCE = <<~RUBY
          module FixtureProject
            class Thing
              def use
                doc = FixtureProject::Documented.new
                doc.
              end
            end
          end
        RUBY

        def test_completes_methods_of_a_typed_local_after_a_trailing_dot
          items = complete(LOCAL_SOURCE, "doc.")

          fetch = find_item(items, "fetch")

          refute_nil fetch
          assert_includes label_details(fetch)[:detail], "key: Symbol"
          assert_equal "Array<String>?", label_details(fetch)[:description]
          assert_equal "Looks up a value.", fetch.attributes[:documentation]
        end

        def test_labels_are_unique
          items = complete(LOCAL_SOURCE, "doc.")

          assert_equal items.map(&:label).uniq, items.map(&:label)
        end

        def test_completion_respects_the_typed_prefix
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  doc = FixtureProject::Documented.new
                  doc.fe
                end
              end
            end
          RUBY

          items = complete(source, "doc.fe")

          refute_empty items
          assert items.all? { |item| item.label.start_with?("fe") }
          assert_includes items.map(&:label), "fetch"
        end

        def test_completion_follows_return_types_through_chains
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  doc = FixtureProject::Documented.new.chain
                  doc.
                end
              end
            end
          RUBY

          items = complete(source, "doc.")

          refute_nil find_item(items, "required_keyword")
        end

        def test_completes_singleton_methods_of_the_class_itself
          items = complete("FixtureProject::Dog.\n", "FixtureProject::Dog.")

          species = find_item(items, "species")

          refute_nil species
          assert_equal "String", label_details(species)[:description]
        end

        def test_completes_singleton_methods_from_extended_modules
          items = complete("FixtureProject::Inferable.\n", "FixtureProject::Inferable.")

          greet = find_item(items, "greet")

          refute_nil greet
          assert_equal "String", label_details(greet)[:description]
        end

        def test_completion_labels_partial_union_members
          items = complete("FixtureProject::Inferable.new.pick_any.\n", "pick_any.")

          bark = find_item(items, "bark")
          fetch = find_item(items, "fetch")

          refute_nil bark
          refute_nil fetch
          assert_includes label_details(bark)[:detail], "FixtureProject::Dog"
          assert_includes label_details(fetch)[:detail], "FixtureProject::Documented"
        end

        def test_completion_ranks_the_receiver_before_ancestors
          items = complete("FixtureProject::InferableChild.new.\n", "InferableChild.")

          labels = items.sort_by { |item| item.attributes[:sortText] }.map(&:label)
          own = labels.index("label")
          inherited = labels.index("names")

          refute_nil own
          refute_nil inherited
          assert_operator own, :<, inherited
        end

        def test_completes_locals_used_inside_a_block
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  doc = FixtureProject::Documented.new
                  [1].each do |value|
                    doc.
                  end
                end
              end
            end
          RUBY

          items = complete(source, "doc.")

          assert_includes items.map(&:label), "fetch"
        end

        def test_combines_union_members_and_duck_methods
          items = complete("FixtureProject::Inferable.new.mixed.\n", "mixed.")

          refute_nil find_item(items, "to_s")
          refute_nil find_item(items, "count")
        end

        def test_completion_on_duck_types_lists_only_the_documented_methods
          items = complete("FixtureProject::Inferable.new.duckish.\n", "duckish.")

          assert_equal %w[inspect to_s], items.map(&:label).sort
        end

        def test_completion_hides_private_methods_from_external_receivers
          source = "FixtureProject::Animal.new.\n"

          items = complete(source, "FixtureProject::Animal.new.")

          refute_empty items
          refute_includes items.map(&:label), "secret"
          refute_includes items.map(&:label), "protected_secret"
        end

        def test_completion_offers_protected_methods_within_the_class_family
          source = <<~RUBY
            module FixtureProject
              class Animal
                # @param other [Animal]
                def compare(other)
                  other.
                end
              end
            end
          RUBY

          items = complete(source, "other.")

          refute_empty items
          assert_includes items.map(&:label), "protected_secret"
        end

        def test_completion_offers_private_methods_for_explicit_self
          source = <<~RUBY
            module FixtureProject
              class Animal
                def use
                  self.
                end
              end
            end
          RUBY

          items = complete(source, "self.")

          assert_includes items.map(&:label), "secret"
        end

        def test_completion_is_disabled_by_settings
          items = nil
          with_server(LOCAL_SOURCE) do |server, uri|
            index_fixtures(server)
            override_addon_settings(enableCompletion: false)
            items = completion_items(server, uri, LOCAL_SOURCE, line_token: "doc.")
          end

          refute_includes items.map(&:label), "fetch"
        end

        def test_completes_core_methods_with_substituted_generics
          items = nil
          source = "[1, 2].\n"

          with_server(source) do |server, uri|
            index_fixtures(server)
            index_core(server)
            wait_for_rbs(server)
            items = completion_items(server, uri, source, line_token: "[1, 2].")
          end

          first = find_item(items, "first")

          refute_nil first
          assert_equal "Integer", label_details(first)[:description]
        end

        def test_completes_core_methods_for_string_receivers
          items = nil
          source = '"text".\n'

          with_server(source) do |server, uri|
            index_fixtures(server)
            index_core(server)
            wait_for_rbs(server)
            items = completion_items(server, uri, source, line_token: '"text".')
          end

          length = find_item(items, "length")

          refute_nil length
          assert_equal "Integer", label_details(length)[:description]
        end

        def test_completion_returns_nothing_for_unknown_receivers
          source = <<~RUBY
            module FixtureProject
              class Thing
                def use
                  mystery.
                end
              end
            end
          RUBY

          assert_empty complete(source, "mystery.")
        end

        def test_completion_does_not_duplicate_host_items
          items = complete("FixtureProject::Inferable.new.pick_any.\n", "pick_any.")
          labels = items.map(&:label)

          assert_equal labels.uniq, labels
        end

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
