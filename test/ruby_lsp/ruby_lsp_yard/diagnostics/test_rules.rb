# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Diagnostics
      # Exercises every rule through the linter against a real index, the way a request would (FR-M5-01..04).
      class TestRules < Minitest::Test
        include DiagnosticsHelpers

        # --- YARD/InvalidTypeSyntax --------------------------------------------------------------------------------

        def test_invalid_type_syntax_is_an_error
          diagnostics = lint(<<~RUBY, rules: [Rules::InvalidTypeSyntax])
            class InvalidSyntaxOwner
              # @param n [Array<
              def call(n); end
            end
          RUBY

          assert_equal ["YARD/InvalidTypeSyntax"], codes(diagnostics)
          assert_equal Constant::DiagnosticSeverity::ERROR, diagnostics.first.severity
          assert_includes diagnostics.first.message, "Array<"
          assert_includes diagnostics.first.message, "@param n"
        end

        def test_valid_type_syntax_passes
          diagnostics = lint(<<~RUBY, rules: [Rules::InvalidTypeSyntax])
            class ValidSyntaxOwner
              # @param n [Array<String>, nil]
              # @return [Hash{Symbol => Integer}]
              def call(n); end
            end
          RUBY

          assert_empty diagnostics
        end

        # --- YARD/UnresolvedType -----------------------------------------------------------------------------------

        def test_unresolved_type_warns
          diagnostics = lint(<<~RUBY, rules: [Rules::UnresolvedType])
            class UnresolvedOwner
              # @return [Nope]
              def call; end
            end
          RUBY

          assert_equal ["YARD/UnresolvedType"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`Nope`"
        end

        def test_resolved_generic_and_type_variable_names_pass
          diagnostics = lint(<<~RUBY, rules: [Rules::UnresolvedType])
            class ResolvedOwner
              # @param items [Array<String>, nil]
              # @param mapping [Hash{T => Integer}]
              # @return [ResolvedOwner]
              def call(items, mapping); end
            end
          RUBY

          assert_empty diagnostics
        end

        # --- YARD/UnknownParam -------------------------------------------------------------------------------------

        def test_unknown_param_warns
          diagnostics = lint(<<~RUBY, rules: [Rules::UnknownParam])
            class UnknownParamOwner
              # @param nope [String]
              # @param args [String]
              # @param blk [Proc]
              # @param kwargs [Hash]
              def call(arg, *args, **kwargs, &blk); end
            end
          RUBY

          assert_equal ["YARD/UnknownParam"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`@param nope`"
        end

        def test_unknown_param_accepts_destructured_parameters
          diagnostics = lint(<<~RUBY, rules: [Rules::UnknownParam])
            class DestructuredParamOwner
              # @param a [Integer]
              # @param b [Integer]
              # @param nope [Integer]
              def call((a, b)); end
            end
          RUBY

          assert_equal ["YARD/UnknownParam"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`@param nope`"
        end

        # --- YARD/DuplicateTag -------------------------------------------------------------------------------------

        def test_duplicate_tags_warn_but_overloads_do_not
          diagnostics = lint(<<~RUBY, rules: [Rules::DuplicateTag])
            class DuplicateOwner
              # @param a [String]
              # @param a [Integer]
              # @return [String]
              # @return [Integer]
              def call(a); end

              # @overload call(a)
              #   @param a [String]
              #   @return [String]
              # @overload call(a, b)
              #   @param a [String]
              #   @param b [String]
              #   @return [String]
              def overloaded(a, b = nil); end
            end
          RUBY

          assert_equal ["YARD/DuplicateTag", "YARD/DuplicateTag"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`@param a`"
          assert_includes diagnostics.last.message, "`@return`"
        end

        # --- YARD/InvalidDirective ---------------------------------------------------------------------------------

        def test_malformed_and_unknown_directives_are_errors
          diagnostics = lint(<<~RUBY, rules: [Rules::InvalidDirective])
            class DirectiveOwner
              # @!bogus
              # @!attribute [r]
              # @!visibility internal
              # @!parse
              #   def broken(
              def call; end
            end
          RUBY

          assert_equal 4, diagnostics.size
          assert diagnostics.all? { |diagnostic| diagnostic.severity == Constant::DiagnosticSeverity::ERROR }
          assert_includes diagnostics.map(&:message), "Unknown directive `@!bogus`"
          assert_includes diagnostics.map(&:message), "`@!attribute` is missing an attribute name"
          assert_includes diagnostics.map(&:message), "`@!visibility` must be one of public, protected, private"
          assert diagnostics.any? { |diagnostic| diagnostic.message.include?("`@!parse` text has a Ruby syntax error") }
        end

        def test_valid_directives_pass
          diagnostics = lint(<<~RUBY, rules: [Rules::InvalidDirective])
            class ValidDirectiveOwner
              # @!method self.build(name)
              #   @param name [String]
              #   @return [ValidDirectiveOwner]
              # @!attribute [rw] label
              #   @return [String]
              # @!visibility private
              # @!parse attr_reader :generated
              # @!group Helpers
              # @!scope class
              # @!endgroup
              def call; end
            end
          RUBY

          assert_empty diagnostics
        end

        # --- YARD/YieldWithoutBlock --------------------------------------------------------------------------------

        def test_yield_tags_require_a_block
          diagnostics = lint(<<~RUBY, rules: [Rules::YieldWithoutBlock])
            class YieldOwner
              # @yieldparam v [String]
              def no_yield(v); end

              # @yield [x]
              def with_yield
                yield 1
              end

              # @yieldreturn [String]
              def with_block(&blk); end
            end
          RUBY

          assert_equal ["YARD/YieldWithoutBlock"], codes(diagnostics)
          assert_equal Constant::DiagnosticSeverity::INFORMATION, diagnostics.first.severity
          assert_includes diagnostics.first.message, "`no_yield`"
        end

        # --- YARD/MissingParam -------------------------------------------------------------------------------------

        def test_missing_param_is_off_by_default
          source = <<~RUBY
            class MissingParamOwner
              # @param a [String]
              # @return [String]
              def call(a, b); end
            end
          RUBY

          assert_empty lint(source)

          diagnostics = lint(source, settings: rules_enabled("YARD/MissingParam"))
          assert_equal ["YARD/MissingParam"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`b`"
        end

        def test_missing_param_ignores_undocumented_and_overloaded_methods
          diagnostics = lint(<<~RUBY, rules: [Rules::MissingParam], settings: rules_enabled("YARD/MissingParam"))
            class MissingParamIgnored
              def undocumented(a); end

              # @overload call(a)
              #   @param a [String]
              #   @return [String]
              def overloaded(a); end
            end
          RUBY

          assert_empty diagnostics
        end

        # --- YARD/MissingReturn ------------------------------------------------------------------------------------

        def test_missing_return_is_off_by_default_and_exempts_special_methods
          source = <<~RUBY
            class MissingReturnOwner
              # @param a [String]
              def public_one(a); end

              # @param a [String]
              def initialize(a); end

              # @param a [String]
              def write=(a); end

              # @param a [String]
              def private_one(a); end
              private :private_one
            end
          RUBY

          assert_empty lint(source)

          diagnostics = lint(source, settings: rules_enabled("YARD/MissingReturn"))
          assert_equal ["YARD/MissingReturn"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`public_one`"
        end

        # --- YARD/ReturnTypeMismatch -------------------------------------------------------------------------------

        def test_return_type_mismatch_checks_literal_returns
          diagnostics = lint(<<~RUBY, rules: [Rules::ReturnTypeMismatch], settings: rules_enabled("YARD/ReturnTypeMismatch"))
            class ReturnMismatchOwner
              # @return [Integer]
              def bad
                return "nope"
              end

              # @return [Integer, nil]
              def guarded
                return nil if false

                1
              end

              # @return [String]
              def ok
                return "yes"
              end
            end
          RUBY

          assert_equal ["YARD/ReturnTypeMismatch"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`return \"nope\"`"
          assert_includes diagnostics.first.message, "`@return [Integer]`"
        end

        # --- YARD/ArgumentTypeMismatch -----------------------------------------------------------------------------

        def test_argument_type_mismatch_checks_literals_against_yard_params
          diagnostics = lint(<<~RUBY, rules: [Rules::ArgumentTypeMismatch], settings: rules_enabled("YARD/ArgumentTypeMismatch"))
            class ArgumentMismatchOwner
              # @param n [Integer]
              # @param key [Symbol]
              def take(n, key:); end

              def use
                take("nope", key: 42)
                take(1, key: :ok)
              end
            end
          RUBY

          assert_equal ["YARD/ArgumentTypeMismatch", "YARD/ArgumentTypeMismatch"], codes(diagnostics)
          assert diagnostics.any? { |diagnostic| diagnostic.message.include?("\"nope\"") && diagnostic.message.include?("@param n") }
          assert diagnostics.any? { |diagnostic| diagnostic.message.include?("42") && diagnostic.message.include?("@param key") }
        end

        def test_argument_type_mismatch_skips_rbs_signatures
          diagnostics = lint(<<~RUBY, rules: [Rules::ArgumentTypeMismatch], settings: rules_enabled("YARD/ArgumentTypeMismatch"))
            class RbsSkipOwner
              def use
                "text".gsub(1)
              end
            end
          RUBY

          assert_empty diagnostics
        end

        def test_argument_type_mismatch_checks_rest_elements_not_the_container
          diagnostics = lint(<<~RUBY, rules: [Rules::ArgumentTypeMismatch], settings: rules_enabled("YARD/ArgumentTypeMismatch"))
            class RestArgsOwner
              # @param args [Array<String>]
              def take(*args); end

              def use
                take("one", "two")
                take(1)
              end
            end
          RUBY

          assert_equal ["YARD/ArgumentTypeMismatch"], codes(diagnostics)
          assert_includes diagnostics.first.message, "`1`"
        end

        def test_argument_type_mismatch_ignores_untyped_rest_containers
          diagnostics = lint(<<~RUBY, rules: [Rules::ArgumentTypeMismatch], settings: rules_enabled("YARD/ArgumentTypeMismatch"))
            class UntypedRestOwner
              # @param args [Array]
              def take(*args); end

              def use
                take(1)
              end
            end
          RUBY

          assert_empty diagnostics
        end

        def test_argument_type_mismatch_uses_option_tags_for_keyword_rest
          diagnostics = lint(<<~RUBY, rules: [Rules::ArgumentTypeMismatch], settings: rules_enabled("YARD/ArgumentTypeMismatch"))
            class OptionTagOwner
              # @param options [Hash]
              # @option options [Boolean] :strict whether to fail
              def configure(**options); end

              def use
                configure(strict: true)
                configure(strict: 42)
                configure(timeout: 42)
              end
            end
          RUBY

          assert_equal ["YARD/ArgumentTypeMismatch"], codes(diagnostics)
          assert_includes diagnostics.first.message, "@option options :strict [Boolean]"
        end

        def test_argument_type_mismatch_needs_inference_and_the_store
          diagnostics = lint_without_index(
            <<~RUBY,
              class NoIndexOwner
                def use
                  take("nope")
                end
              end
            RUBY
            rules: [Rules::ArgumentTypeMismatch],
            settings: rules_enabled("YARD/ArgumentTypeMismatch")
          )

          assert_empty diagnostics
        end

        private

        def rules_enabled(*keys, severity: "warning")
          {"diagnosticRules" => keys.to_h { |key| [key, severity] }}
        end
      end
    end
  end
end
