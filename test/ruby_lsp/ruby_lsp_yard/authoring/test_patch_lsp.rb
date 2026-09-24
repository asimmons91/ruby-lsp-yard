# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Authoring
      # Exercises the D3 monkeypatch through real LSP requests: comment completion, pass-through, hover, definition
      # and the skeleton code action (FR-M4-P1..P6, FR-M4-01..06).
      class TestPatchLsp < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        COMMENT_SOURCE = <<~RUBY
          module FixtureProject
            class Documented
              # @param existing [String]
              # @ret
              def fetch(existing, missing)
                raise KeyError
              end
            end
          end
        RUBY

        CODE_SOURCE = <<~RUBY
          module FixtureProject
            class Thing
              def use
                doc = FixtureProject::Documented.new
                doc.
              end
            end
          end
        RUBY

        def test_comment_completion_returns_tag_items_with_snippets
          items = comment_items(COMMENT_SOURCE, "# @ret", snippet_support: true)

          item = items.find { |candidate| candidate.filter_text == "@return" }
          refute_nil item
          assert_equal "@return [${1:Type}] $0", item.text_edit.new_text
          assert_equal 2, item.insert_text_format
          assert_includes items.map(&:label), "@param missing []"
          refute_includes items.map(&:label), "@param existing []"
        end

        # Ruby LSP 0.26 applies client capabilities before add-ons load, so the capability is usually unknown; the
        # add-on then assumes snippet support (NFR-C3).
        def test_comment_completion_assumes_snippets_when_the_capability_is_unknown
          item = comment_items(COMMENT_SOURCE, "# @ret").find { |candidate| candidate.filter_text == "@return" }

          refute_nil item
          assert_equal "@return [${1:Type}] $0", item.text_edit.new_text
          assert_equal 2, item.insert_text_format
        end

        def test_comment_completion_skips_destructured_and_anonymous_parameters
          source = <<~RUBY
            module FixtureProject
              class Documented
                # @ret
                def process((left, right), *, key:, **, &)
                end
              end
            end
          RUBY
          labels = comment_items(source, "# @ret", snippet_support: true).map(&:label)

          assert_includes labels, "@param key []"
          assert_includes labels, "@yield [args]"
          refute labels.any? { |label| label.start_with?("@param  ") }
        end

        def test_comment_completion_degrades_to_plain_text_without_snippet_support
          item = comment_items(COMMENT_SOURCE, "# @ret", snippet_support: false)
            .find { |candidate| candidate.filter_text == "@return" }

          refute_nil item
          assert_equal "@return [Type]", item.text_edit.new_text
          assert_nil item.attributes[:insertTextFormat]
        end

        def test_enable_snippets_setting_disables_snippet_placeholders
          item = comment_items(COMMENT_SOURCE, "# @ret", settings: {enableSnippets: false})
            .find { |candidate| candidate.filter_text == "@return" }

          refute_nil item
          assert_equal "@return [Type]", item.text_edit.new_text
        end

        def test_type_completion_uses_indexed_constants
          source = <<~RUBY
            module FixtureProject
              class Documented
                # @param existing [Doc
                def fetch(existing); end
              end
            end
          RUBY
          labels = comment_items(source, "[Doc").map(&:label)

          assert_includes labels, "Documented"
          assert_includes labels, "Boolean"
        end

        def test_completion_in_code_is_unchanged_by_the_patch
          with_authoring = code_labels(authoring: true)
          without_authoring = code_labels(authoring: false)

          refute_empty with_authoring
          assert_equal without_authoring, with_authoring
        end

        def test_authoring_can_be_disabled
          items = nil
          with_server(COMMENT_SOURCE) do |server, uri|
            override_addon_settings({enableAuthoring: false})
            items = completion_items(server, uri, COMMENT_SOURCE, line_token: "# @ret")
          end

          assert_empty items
        end

        def test_exceptions_inside_the_patch_fall_back_to_the_original_behavior
          items = nil
          Context.stub(:build, ->(*) { raise "boom" }) do
            with_server(COMMENT_SOURCE) do |server, uri|
              items = completion_items(server, uri, COMMENT_SOURCE, line_token: "# @ret")
            end
          end

          assert_empty items
        end

        def test_comment_hover_shows_the_class_documentation
          source = <<~RUBY
            module FixtureProject
              class Thing
                # @param animal [FixtureProject::Animal] the animal
                def take(animal); end
              end
            end
          RUBY
          value = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            value = hover_text(server, uri, source, line_token: "FixtureProject::Animal", position_token: "Animal")
          end

          refute_nil value
          assert_includes value, "class FixtureProject::Animal"
        end

        def test_comment_definition_jumps_to_the_constant
          source = <<~RUBY
            module FixtureProject
              class Thing
                # @param animal [FixtureProject::Animal] the animal
                def take(animal); end
              end
            end
          RUBY
          links = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            links = definition_links(
              server,
              uri,
              source,
              line_token: "FixtureProject::Animal",
              position_token: "Animal"
            )
          end

          refute_empty links
          assert_match(/animals\.rb/, links.first.target_uri)
        end

        def test_code_action_adds_a_skeleton_to_an_undocumented_def
          source = <<~RUBY
            module FixtureProject
              class Thing
                def brand_new(one, two)
                  [one, two]
                end
              end
            end
          RUBY
          actions = nil
          with_server(source) do |server, uri|
            actions = code_actions(server, uri, source, line_token: "def brand_new", position_token: "def")
          end

          action = actions.find { |candidate| candidate.title == "Add YARD documentation" }
          refute_nil action
          text = action.edit.changes.values.flatten.first.new_text
          assert_includes text, "# @param one [Type]"
          assert_includes text, "# @param two [Type]"
          assert_includes text, "# @return [Type]"
        end

        # Regression: the line above a top-of-file `def` is not the file's last line.
        def test_code_action_is_offered_for_a_top_of_file_def_followed_by_a_comment
          source = "def brand_new(one); end\n# trailing comment\n"
          actions = nil
          with_server(source) do |server, uri|
            actions = code_actions(server, uri, source, line_token: "def brand_new", position_token: "def")
          end

          refute_nil actions.find { |candidate| candidate.title == "Add YARD documentation" }
        end

        def test_code_action_is_not_offered_for_documented_defs
          source = <<~RUBY
            module FixtureProject
              class Thing
                # @return [String]
                def label; "thing"; end
              end
            end
          RUBY
          actions = nil
          with_server(source) do |server, uri|
            actions = code_actions(server, uri, source, line_token: "def label", position_token: "def")
          end

          assert_nil actions.find { |candidate| candidate.title == "Add YARD documentation" }
        end

        def test_registry_is_cleared_on_deactivate
          registry = nil
          with_server("# a comment\ndef foo; end\n") do |_server, _uri|
            registry = Registry.current
          end

          refute_nil registry
          assert_nil Registry.current
        end

        private

        def comment_items(source, line_token, snippet_support: nil, settings: nil)
          items = nil
          with_server(source) do |server, uri|
            apply_snippet_support(server, snippet_support) unless snippet_support.nil?
            override_addon_settings(settings) if settings
            items = completion_items(server, uri, source, line_token: line_token)
          end
          items
        end

        def code_labels(authoring:)
          labels = nil
          with_server(CODE_SOURCE) do |server, uri|
            override_addon_settings({enableAuthoring: authoring})
            index_fixtures(server)
            labels = completion_items(server, uri, CODE_SOURCE, line_token: "doc.")
              .map { |item| [item.label, item.kind] }
              .sort
          end
          labels
        end

        def apply_snippet_support(server, supported)
          server.global_state.apply_options({
            capabilities: {
              textDocument: {completion: {completionItem: {snippetSupport: supported}}}
            }
          })
        end
      end
    end
  end
end
