# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Diagnostics
      # Runs the registered linter through real LSP requests, the way an editor pulls diagnostics (FR-M5-01..04).
      class TestLinterLsp < Minitest::Test
        include RubyLsp::TestHelper
        include DiagnosticsHelpers
        include LspHelpers

        # The host only computes diagnostics for files inside the workspace.
        FILE_URI = URI::Generic.from_path(path: File.join(Dir.pwd, "test", "fixtures", "project", "lib", "documented.rb"))

        SOURCE = <<~RUBY
          class LspDiagnosticsOwner
            # @param nope [String]
            # @return [String]
            def call(a); end
          end
        RUBY

        def test_the_configured_linter_reports_diagnostics
          items = diagnostics_for(SOURCE)

          item = items.find { |candidate| candidate.code == "YARD/UnknownParam" }
          refute_nil item
          assert_equal "YARD", item.source
          assert_equal Constant::DiagnosticSeverity::WARNING, item.severity
          assert_includes item.message, "`@param nope`"
        end

        def test_diagnostics_do_not_run_unless_the_linter_is_listed
          assert_empty diagnostics_for(SOURCE, linters: [])
          assert_empty diagnostics_for(SOURCE, linters: ["rubocop_internal"])
        end

        def test_suppression_is_honored_through_the_lsp_request
          assert_empty diagnostics_for(<<~RUBY)
            class LspSuppressedOwner
              # @param nope [String]
              # yard:disable YARD/UnknownParam
              def call(a); end
            end
          RUBY
        end

        def test_diagnostics_are_recomputed_after_an_edit
          items = nil
          # `.dup` because the host mutates the document source in place; the heredoc literal is frozen.
          with_server(SOURCE.dup, FILE_URI) do |server, uri|
            index_core(server)
            server.global_state.apply_options(initializationOptions: {linters: ["yard"]})
            refute_empty diagnostic_items(server, uri)

            # `@param nope` -> `@param a` (line 1, characters 11..15).
            server.process_message({
              method: "textDocument/didChange",
              params: {
                textDocument: {uri: uri, version: 2},
                contentChanges: [{
                  range: {start: {line: 1, character: 11}, end: {line: 1, character: 15}},
                  text: "a"
                }]
              }
            })

            items = diagnostic_items(server, uri)
          end

          assert_empty items
        end

        def test_quick_fixes_are_offered_for_diagnostics
          source = <<~RUBY
            class LspQuickFixOwner
              # @param nope [String]
              def call(name); end
            end
          RUBY

          actions = nil
          with_server(source, FILE_URI) do |server, uri|
            index_core(server)
            server.global_state.apply_options(initializationOptions: {linters: ["yard"]})
            actions = code_actions(server, uri, source, line_token: "# @param nope", position_token: "nope")
          end

          action = actions.find { |candidate| candidate.title == "Rename `@param nope` to `@param name`" }
          refute_nil action
          edit = action.edit.changes.values.flatten.first
          assert_equal "name", edit.new_text
        end

        def test_quick_fixes_require_authoring
          source = <<~RUBY
            class LspQuickFixDisabledOwner
              # @param nope [String]
              def call(name); end
            end
          RUBY

          actions = nil
          with_server(source, FILE_URI) do |server, uri|
            index_core(server)
            server.global_state.apply_options(initializationOptions: {linters: ["yard"]})
            override_addon_settings({enableAuthoring: false})
            actions = code_actions(server, uri, source, line_token: "# @param nope", position_token: "nope")
          end

          assert_nil actions.find { |candidate| candidate.title.start_with?("Rename") }
        end

        private

        def diagnostics_for(source, linters: ["yard"])
          items = nil
          with_server(source, FILE_URI) do |server, uri|
            index_core(server)
            server.global_state.apply_options(initializationOptions: {linters: linters})
            items = diagnostic_items(server, uri)
          end
          items
        end
      end
    end
  end
end
