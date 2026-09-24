# frozen_string_literal: true

require_relative "support"
require "ruby_lsp_yard/rbs"

adapter = RubyLsp::Yard::Indexer.wrap(BenchmarkSupport.index)
loader = RubyLsp::Yard::Rbs::Loader.new(background: false)
loader.start
store = RubyLsp::Yard::SignatureStore.new(adapter, rbs: RubyLsp::Yard::Rbs::Source.new(loader))
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

core_context = BenchmarkSupport.context_for("[1, 2].first\n", "first")
BenchmarkSupport.measure("generic core return") do
  engine.type_for(core_context.node, core_context)
end

block_context = BenchmarkSupport.context_for("\"a,b\".split(\",\").map(&:strip)\n", "map(&:strip)")
BenchmarkSupport.measure("block return inference") do
  engine.type_for(block_context.node, block_context)
end
