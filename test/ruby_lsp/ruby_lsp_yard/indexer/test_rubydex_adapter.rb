# frozen_string_literal: true

require "test_helper"

# The Rubydex backend only exists on Ruby LSP 0.27+. It satisfies the same AdapterContract as the RubyIndexer
# backend (FR-M6-01, FR-M6-04).
if defined?(RubyLsp::Yard::Indexer::RubydexAdapter)
  module RubyLsp
    module Yard
      module Indexer
        class TestRubydexAdapter < Minitest::Test
          include AdapterContract
          include IndexHelpers

          def build_adapter(index)
            RubydexAdapter.new(index)
          end

          def test_factory_builds_the_rubydex_backend
            global_state = Struct.new(:graph).new(index)

            assert_instance_of RubydexAdapter, Indexer.for(global_state)
          end

          # Rubydex names `attr_*` members after the reader; the adapter derives the writer, so the contract's
          # attribute assertions are backed by synthesized definitions on this backend.
          def test_accessor_writers_are_synthesized_from_the_reader_member
            definitions = adapter.attribute_definitions(ANIMAL, "age")
            writer = definitions.find { |definition| definition.name == "age=" }

            refute_nil writer
            assert_equal :attribute, writer.kind
            assert_equal ANIMAL, writer.owner
            assert_includes writer.comments, "@return [Integer]"
            assert_equal [Parameter.new(:value, :required)], writer.parameters
          end

          def test_method_definitions_accept_writer_names
            writer = adapter.method_definitions(ANIMAL, "age=").first
            reader = adapter.method_definitions(ANIMAL, "name").first

            refute_nil writer
            assert_equal "age=", writer.name
            assert_equal :attribute, writer.kind
            refute_nil reader
            assert_equal "name", reader.name
          end

          def test_singleton_owners_use_the_ruby_indexer_spelling
            definition = adapter.method_definitions(DOG, "species", singleton: true).first

            refute_nil definition
            assert_equal "#{DOG}::<Class:Dog>", definition.owner
          end
        end
      end
    end
  end
end
