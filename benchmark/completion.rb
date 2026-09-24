# frozen_string_literal: true

require_relative "support"

adapter = RubyLsp::Yard::Indexer.wrap(BenchmarkSupport.index)
store = RubyLsp::Yard::SignatureStore.new(adapter)

# The expensive part of completion is collecting candidates without reading comments and enriching the documented
# ones with YARD signatures. This mirrors what the listener does per request once the receiver is resolved.
BenchmarkSupport.measure("completion enrichment") do
  adapter.completion_candidates("FixtureProject::Documented").each do |definition|
    store.lookup(definition.owner, definition.name)
  end
end

puts "budgets: completion p95 <= 50 ms (NFR-P2), inference p95 <= 20 ms (NFR-P3)"
