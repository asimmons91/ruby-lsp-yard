# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Diagnostics
      # Quick-fix construction (FR-M5-03): renaming an unknown `@param`, adding a missing `@param` and fixing an
      # unresolved type name.
      class TestFixes < Minitest::Test
        include DiagnosticsHelpers

        def test_renames_an_unknown_param_to_the_closest_parameter
          actions = fix_actions(<<~RUBY, line: 1, character: 10)
            class FixRenameOwner
              # @param nope [String]
              def call(name); end
            end
          RUBY

          action = actions.find { |candidate| candidate.title == "Rename `@param nope` to `@param name`" }
          refute_nil action
          assert_equal Constant::CodeActionKind::QUICK_FIX, action.kind
          edit = action.edit.changes.values.flatten.first
          assert_equal "name", edit.new_text
          assert_equal 1, edit.range.start.line
          assert_equal 11, edit.range.start.character
          assert_equal 15, edit.range.end.character
        end

        def test_does_not_rename_when_no_candidate_is_close
          actions = fix_actions(<<~RUBY, line: 1, character: 10)
            class FixNoRenameOwner
              # @param completely_unrelated [String]
              def call(name); end
            end
          RUBY

          assert_empty actions
        end

        def test_adds_a_missing_param_tag
          actions = fix_actions(
            <<~RUBY,
              class FixAddParamOwner
                # @param a [String]
                # @return [String]
                def call(a, b); end
              end
            RUBY
            line: 3,
            character: 8,
            settings: {"diagnosticRules" => {"YARD/MissingParam" => "warning"}}
          )

          action = actions.find { |candidate| candidate.title == "Add `@param b`" }
          refute_nil action
          edit = action.edit.changes.values.flatten.first
          assert_equal "  # @param b [Type]\n", edit.new_text
          assert_equal 3, edit.range.start.line
          assert_equal 0, edit.range.start.character
        end

        def test_prefills_the_missing_param_type_from_inherited_documentation
          actions = fix_actions(
            <<~RUBY,
              class FixAddParamBase
                # @param b [Integer]
                def call(a, b); end
              end

              class FixAddParamChild < FixAddParamBase
                # @param a [String]
                def call(a, b); end
              end
            RUBY
            line: 7,
            character: 8,
            settings: {"diagnosticRules" => {"YARD/MissingParam" => "warning"}}
          )

          action = actions.find { |candidate| candidate.title == "Add `@param b`" }
          refute_nil action
          edit = action.edit.changes.values.flatten.first
          assert_equal "  # @param b [Integer]\n", edit.new_text
        end

        def test_fixes_an_unresolved_type_name
          actions = fix_actions(<<~RUBY, line: 1, character: 14)
            class FixTypeOwner
              # @return [Strng]
              def call; end
            end
          RUBY

          action = actions.find { |candidate| candidate.title == "Change `Strng` to `String`" }
          refute_nil action
          edit = action.edit.changes.values.flatten.first
          assert_equal "String", edit.new_text
          assert_equal 13, edit.range.start.character
          assert_equal 18, edit.range.end.character
        end

        def test_does_not_offer_actions_for_suppressed_findings
          actions = fix_actions(<<~RUBY, line: 1, character: 10)
            class FixSuppressedOwner
              # @param nope [String]
              # yard:disable YARD/UnknownParam
              def call(name); end
            end
          RUBY

          assert_empty actions
        end

        def test_does_not_offer_actions_outside_the_requested_range
          actions = fix_actions(<<~RUBY, line: 4)
            class FixRangeOwner
              # @param nope [String]
              def call(name); end

              def other; end
            end
          RUBY

          assert_empty actions
        end

        def test_does_not_fix_resolved_types
          actions = fix_actions(<<~RUBY, line: 1, character: 14)
            class FixResolvedOwner
              # @return [String]
              def call; end
            end
          RUBY

          assert_empty actions
        end
      end
    end
  end
end
