# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    # The M3 acceptance corpus (requirements §8): chains through core classes resolve with generics (`Array#first`),
    # block parameters are typed from RBS block signatures (`Hash#each`), and block returns bind method type
    # variables (`map`).
    class TestM3Corpus < Minitest::Test
      include RubyLsp::TestHelper
      include IndexHelpers
      include LspHelpers
      include InferenceHelpers

      class << self
        def core_index
          @core_index ||= Object.new.extend(IndexHelpers).build_core_index
        end

        def rbs_source
          @rbs_source ||= IndexHelpers.rbs_source
        end
      end

      def setup
        @adapter = Indexer.wrap(self.class.core_index)
        @store = SignatureStore.new(@adapter, rbs: self.class.rbs_source)
        @engine = Inference::Engine.new(adapter: @adapter, store: @store)
      end

      def test_infers_generic_core_returns
        assert_equal Types::Instance.new("Integer"), type_of("[1, 2].first")
        assert_equal Types::Instance.new("String"), type_of('["a", "b"].first')
        assert_equal Types::Instance.new("Array", [Types::Instance.new("String")]), type_of('"a,b".split(",")')
      end

      def test_types_block_parameters_from_rbs_signatures
        source = "def work\n  {a: 1}.each { |k, v| v }\nend\n"

        assert_equal Types::Instance.new("Integer"), type_at(source, "| v")
      end

      def test_infers_block_return_types
        assert_equal(
          Types::Instance.new("Array", [Types::Instance.new("String")]),
          type_of('"a,b".split(",").map(&:strip)')
        )
      end

      def test_completes_core_methods_with_generic_types
        items = complete("[1, 2].\n", "[1, 2].")
        first = items.find { |item| item.label == "first" }

        refute_nil first
        assert_equal "Integer", label_details(first)[:description]
        assert_equal items.map(&:label).uniq, items.map(&:label)
      end

      private

      def complete(source, line_token)
        items = nil
        with_server(source) do |server, uri|
          index_fixtures(server)
          index_core(server)
          wait_for_rbs(server)
          items = completion_items(server, uri, source, line_token: line_token)
        end

        items
      end

      def type_of(expression)
        source = "def work\n  value = #{expression}\nend\n"
        document = document_for(source)
        write = find_node(document.ast, Prism::LocalVariableWriteNode)
        context = context_for(source, "value =")

        @engine.type_for(write.value, context)
      end

      def type_at(source, marker)
        context = context_for(source, marker)

        @engine.type_for(context.node, context)
      end
    end
  end
end
