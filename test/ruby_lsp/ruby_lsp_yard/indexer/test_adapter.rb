# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Indexer
      class TestAdapter < Minitest::Test
        def test_the_interface_is_abstract
          adapter = Adapter.new

          assert_raises(NotImplementedError) { adapter.method_definitions("Foo", "bar") }
          assert_raises(NotImplementedError) { adapter.attribute_definitions("Foo", "bar") }
          assert_raises(NotImplementedError) { adapter.constant_definitions("Foo") }
          assert_raises(NotImplementedError) { adapter.resolve_constant("Foo", []) }
          assert_raises(NotImplementedError) { adapter.ancestors("Foo") }
          assert_raises(NotImplementedError) { adapter.methods_of("Foo") }
          assert_raises(NotImplementedError) { adapter.completion_candidates("Foo") }
        end

        def test_on_change_dispatches_to_subscribers
          adapter = Adapter.new
          changed = []
          adapter.subscribe { |uris| changed.concat(uris) }
          uri = URI("file:///foo.rb")

          adapter.on_change([uri])

          assert_equal [uri], changed
        end

        def test_on_change_isolates_failing_subscribers
          adapter = Adapter.new
          called = false
          adapter.subscribe { |_uris| raise "boom" }
          adapter.subscribe { |_uris| called = true }

          adapter.on_change([URI("file:///foo.rb")])

          assert called
        end

        def test_on_change_ignores_empty_input
          adapter = Adapter.new
          called = false
          adapter.subscribe { |_uris| called = true }

          adapter.on_change([])
          adapter.on_change(nil)

          refute called
        end
      end
    end
  end
end
