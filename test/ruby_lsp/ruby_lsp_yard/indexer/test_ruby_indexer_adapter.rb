# frozen_string_literal: true

require "test_helper"

# The RubyIndexer backend only exists on Ruby LSP 0.26.x. On 0.27 the Rubydex backend is exercised instead
# (FR-M6-04).
if defined?(RubyLsp::Yard::Indexer::RubyIndexerAdapter)
  module RubyLsp
    module Yard
      module Indexer
        class TestRubyIndexerAdapter < Minitest::Test
          include AdapterContract
          include IndexHelpers

          def build_adapter(index)
            RubyIndexerAdapter.new(index)
          end

          def test_factory_builds_the_ruby_indexer_backend
            global_state = Struct.new(:index).new(index)

            assert_instance_of RubyIndexerAdapter, Indexer.for(global_state)
          end
        end
      end
    end
  end
end
