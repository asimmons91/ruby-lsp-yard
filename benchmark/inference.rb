# frozen_string_literal: true

require_relative "support"

adapter = RubyLsp::Yard::Indexer::RubyIndexerAdapter.new(BenchmarkSupport.index)
store = RubyLsp::Yard::SignatureStore.new(adapter)
engine = RubyLsp::Yard::Inference::Engine.new(adapter: adapter, store: store)

source = <<~RUBY
  module FixtureProject
    class Thing
      def use(param)
        doc = FixtureProject::Documented.new
        other = doc.chain
        names = FixtureProject::Inferable.new.names
        doc.fetch(:key)
      end
    end
  end
RUBY
context = BenchmarkSupport.context_for(source, "doc.fetch")

puts "inference (#{BenchmarkSupport::ITERATIONS} iterations, warm cache)"
BenchmarkSupport.measure("local receiver") do
  receiver = context.node.receiver
  engine.type_for(receiver, context)
end

chain_context = BenchmarkSupport.context_for("FixtureProject::Documented.new.chain.label\n", "chain.label")
BenchmarkSupport.measure("chained receiver") do
  receiver = chain_context.node.receiver
  engine.type_for(receiver, chain_context)
end

BenchmarkSupport.measure("resolution with union/duck") do
  engine.resolution_for(BenchmarkSupport.context_for("FixtureProject::Inferable.new.pick_any.\n", "pick_any."))
end
