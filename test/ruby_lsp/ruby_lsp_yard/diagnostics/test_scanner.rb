# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Diagnostics
      class TestScanner < Minitest::Test
        include DiagnosticsHelpers

        def test_finds_method_targets_with_their_comment_block
          targets = scan(<<~RUBY)
            module Demo
              class Thing
                # Fetches a thing.
                # @param n [Integer] the number
                # @return [String]
                def fetch(n)
                  n
                end
              end
            end
          RUBY

          target = targets.first
          assert_equal :method, target.kind
          assert_equal "fetch", target.name
          assert_equal "Demo::Thing", target.owner
          assert_equal ["Demo", "Thing"], target.nesting
          refute target.singleton
          assert_equal :public, target.visibility
          assert_equal [:required], target.parameters.map(&:kind)
          assert target.documented?
          assert_equal 3, target.comment_start_line
          assert_equal 3, target.comment_lines.size
          assert_equal 6, target.location.start_line
        end

        def test_singleton_methods_and_class_bodies
          targets = scan(<<~RUBY)
            class Thing
              # @return [String]
              def self.build; end

              class << self
                # @return [Integer]
                def count; end
              end
            end
          RUBY

          assert_equal [["build", true], ["count", true]], targets.map { |target| [target.name, target.singleton] }
        end

        def test_attribute_calls_become_one_target
          target = scan(<<~RUBY).first
            class Thing
              # @return [String]
              attr_reader :name, :label
            end
          RUBY

          assert_equal :attribute, target.kind
          assert_equal %w[name label], target.attr_names
          assert_equal "Thing", target.owner
        end

        def test_namespace_and_constant_targets
          targets = scan(<<~RUBY)
            # @!method build(name)
            module Demo
              # @return [String]
              MAX = "max"
            end
          RUBY

          assert_equal [:namespace, :constant], targets.map(&:kind)
          assert_equal ["Demo", "MAX"], targets.map(&:name)
        end

        def test_tracks_visibility
          targets = scan(<<~RUBY)
            class Thing
              # @return [String]
              def public_one; end

              private

              # @return [String]
              def private_one; end

              # @return [String]
              def made_private; end
              private :made_private

              protected

              # @return [String]
              private def declared_private; end
            end
          RUBY

          assert_equal(
            [["public_one", :public], ["private_one", :private], ["made_private", :private], ["declared_private", :private]],
            targets.map { |target| [target.name, target.visibility] }
          )
        end

        def test_ignores_trailing_comments
          targets = scan(<<~RUBY)
            class Thing
              def one; end # @return [String]

              # @return [String]
              def two; end
            end
          RUBY

          assert_equal ["two"], targets.map(&:name)
        end

        def test_ignores_comment_blocks_without_tags
          targets = scan(<<~RUBY)
            class Thing
              # Just prose about the method below.
              def one; end

              # @return [String]
              def two; end
            end
          RUBY

          assert_equal ["two"], targets.map(&:name)
        end

        def test_does_not_scan_method_bodies
          targets = scan(<<~RUBY)
            class Thing
              def outer
                # @return [String]
                def inner; end
              end
            end
          RUBY

          assert_empty targets
        end

        def test_scans_defs_inside_class_level_dsl_blocks
          targets = scan(<<~RUBY)
            class Thing
              included do
                # @return [String]
                def from_dsl; end
              end
            end
          RUBY

          assert_equal ["from_dsl"], targets.map(&:name)
          assert_equal "Thing", targets.first.owner
        end

        def test_parses_suppression_directives
          target = scan(<<~RUBY).first
            class Thing
              # @return [String]
              # yard:disable YARD/UnknownParam
              def one; end
            end
          RUBY

          assert target.suppressed?("YARD/UnknownParam")
          refute target.suppressed?("YARD/DuplicateTag")
        end

        private

        def scan(source)
          scanner_for(source).targets
        end
      end
    end
  end
end
