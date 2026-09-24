# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    # The M2 acceptance corpus (requirements §7): completion after `.` on receivers whose types come from YARD tags.
    # Accuracy must be at least 90%; labels listed under `forbidden` must never be offered.
    class TestCompletionCorpus < Minitest::Test
      include RubyLsp::TestHelper
      include IndexHelpers
      include LspHelpers

      CASES = [
        {
          name: "typed local from an assignment",
          source: <<~RUBY,
            module FixtureProject
              class Thing
                def use
                  doc = FixtureProject::Documented.new
                  doc.
                end
              end
            end
          RUBY
          line_token: "doc.",
          expected: %w[fetch find chain each_value required_keyword label splats],
          forbidden: %w[secret]
        },
        {
          name: "constant instance",
          source: "FixtureProject::Animal.new.\n",
          line_token: "FixtureProject::Animal.new.",
          expected: %w[speak signature only_one],
          forbidden: %w[secret]
        },
        {
          name: "subclass with inherited methods",
          source: "FixtureProject::Dog.new.\n",
          line_token: "FixtureProject::Dog.new.",
          expected: %w[bark speak signature],
          forbidden: %w[secret]
        },
        {
          name: "singleton with an extended module",
          source: "FixtureProject::Inferable.\n",
          line_token: "FixtureProject::Inferable.",
          expected: %w[greet],
          forbidden: []
        },
        {
          name: "chain returning self",
          source: "FixtureProject::Documented.new.chain.\n",
          line_token: "chain.",
          expected: %w[fetch find label],
          forbidden: []
        },
        {
          name: "union members",
          source: "FixtureProject::Inferable.new.pick_any.\n",
          line_token: "pick_any.",
          expected: %w[bark fetch find label],
          forbidden: %w[secret]
        },
        {
          name: "duck type",
          source: "FixtureProject::Inferable.new.duckish.\n",
          line_token: "duckish.",
          expected: %w[to_s inspect],
          forbidden: %w[fetch pick_any]
        },
        {
          name: "instance variable from class assignments",
          source: <<~RUBY,
            module FixtureProject
              class Inferable
                def use
                  @related.
                end
              end
            end
          RUBY
          line_token: "@related.",
          expected: %w[fetch label find],
          forbidden: %w[secret]
        }
      ].freeze

      def test_completion_accuracy_on_the_m2_corpus
        found = 0
        total = 0

        CASES.each do |test_case|
          labels = complete(test_case[:source], test_case[:line_token]).map(&:label)

          test_case[:expected].each do |label|
            total += 1
            found += 1 if labels.include?(label)
          end

          test_case[:forbidden].each do |label|
            refute_includes labels, label, "#{test_case[:name]} offered #{label}"
          end
        end

        accuracy = found.to_f / total

        assert_operator accuracy, :>=, 0.9, "completion corpus accuracy was #{accuracy}"
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
    end
  end
end
