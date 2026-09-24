# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Authoring
      class TestPatch < Minitest::Test
        def test_only_tested_versions_are_supported
          assert Patch.supported_version?("0.26.11")
          assert Patch.supported_version?("0.27.0.beta5")
          refute Patch.supported_version?("0.26.10")
          refute Patch.supported_version?("0.27.0")
          refute Patch.supported_version?("0.27.0.beta4")
        end

        # FR-M4-P2: bumping the installed Ruby LSP must update the tested-versions list.
        def test_the_installed_ruby_lsp_version_is_tested
          assert Patch.supported_version?(RubyLsp::VERSION),
            "Ruby LSP #{RubyLsp::VERSION} is not in #{Patch::TESTED_VERSIONS.inspect}"
        end

        def test_install_is_idempotent
          assert Patch.install!
          Patch.install!

          assert_equal 1, RubyLsp::Requests::Completion.ancestors.count(Patch::CompletionPatch)
          assert_equal 1, RubyLsp::Requests::Hover.ancestors.count(Patch::HoverPatch)
          assert_equal 1, RubyLsp::Requests::Definition.ancestors.count(Patch::DefinitionPatch)
          assert_equal 1, RubyLsp::Requests::CodeActions.ancestors.count(Patch::CodeActionsPatch)
          assert_equal 1, RubyLsp::ClientCapabilities.ancestors.count(Patch::ClientCapabilitiesPatch)
        end

        # FR-M4-P5: the patch notes the exact upstream methods it replaces, so upgrades fail loudly when one moves.
        def test_patched_methods_still_exist_on_the_host
          Patch::PATCHED_METHODS.each do |class_name, methods|
            klass = Object.const_get(class_name)
            methods.each do |name|
              defined = klass.method_defined?(name) || klass.private_method_defined?(name)
              assert defined, "#{class_name}##{name} is missing on Ruby LSP #{RubyLsp::VERSION}"
            end
          end
        end

        def test_registry_defaults_to_disabled
          saved = Registry.current
          Registry.current = nil

          refute Registry.authoring?
          refute Registry.comment_hover?
          refute Registry.comment_definition?
          refute Registry.snippets?
          assert_nil Registry.adapter
          assert_nil Registry.store
        ensure
          Registry.current = saved
        end
      end
    end
  end
end
