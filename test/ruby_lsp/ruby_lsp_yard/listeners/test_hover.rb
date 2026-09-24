# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestHover < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers

        def test_hover_shows_types_for_foo_new_receivers
          source = "FixtureProject::Documented.new.fetch(:key)\n"

          value = hover_on(source, "fetch")

          refute_nil value
          assert_includes value, "def fetch(key: Symbol, default = ...: String?, limit: Integer = ..., **options: Hash, &block)"
          assert_includes value, "→ Array<String>?"
          assert_includes value, "**Option:** `:strict` (`Boolean`)"
        end

        def test_hover_shows_types_for_self_receivers
          source = <<~RUBY
            module FixtureProject
              class Animal
                def talk
                  speak("!")
                end
              end
            end
          RUBY

          value = hover_on(source, "speak")

          refute_nil value
          assert_includes value, "def speak(suffix: String) → String"
        end

        def test_hover_shows_types_for_constant_receivers
          source = "FixtureProject::Dog.species\n"

          value = hover_on(source, "species")

          refute_nil value
          assert_includes value, "def self.species() → String"
        end

        def test_hover_shows_yield_tags
          source = "FixtureProject::Documented.new.each_value { |value| value }\n"

          value = hover_on(source, "each_value")

          refute_nil value
          assert_includes value, "**Yields:** `value` (`String`) — the value"
          assert_includes value, "**Yields:** `Integer` (return)"
        end

        def test_hover_shows_overloads
          source = "FixtureProject::Documented.new.find(:key)\n"

          value = hover_on(source, "find")

          refute_nil value
          assert_includes value, "def find(key: Symbol) → String"
          assert_includes value, "def find(key: Symbol, default: String) → String"
        end

        def test_hover_does_not_emit_without_yard_types
          source = "FixtureProject::Animal.new.class\n"

          value = hover_on(source, "class")

          return if value.nil?

          refute_includes value, "```ruby"
        end

        def test_hover_is_disabled_by_settings
          source = "FixtureProject::Dog.species\n"

          value = hover_on(source, "species", disable: true)

          refute_includes value.to_s, "def self.species"
        end

        private

        def hover_on(source, token, disable: false)
          value = nil

          with_server(source) do |server, uri|
            index_fixtures(server)
            disable_hover(server) if disable
            value = request_hover(server, uri, source, token)
          end

          value
        end

        def request_hover(server, uri, source, token)
          line = source.lines.index { |candidate| candidate.include?(token) }
          character = source.lines[line].index(token) + 1
          server.process_message({
            id: 1,
            method: "textDocument/hover",
            params: {textDocument: {uri: uri}, position: {line: line, character: character}}
          })
          response = pop_result(server).response
          response&.contents&.value
        end

        def index_fixtures(server)
          FIXTURE_FILES.each { |file| server.global_state.index.index_file(fixture_uri(file)) }
        end

        def disable_hover(server)
          addon = RubyLsp::Addon.addons.find { |candidate| candidate.name == "Ruby LSP YARD" }
          addon.define_singleton_method(:settings) { Settings.new({enableHover: false}) }
        end
      end
    end
  end
end
