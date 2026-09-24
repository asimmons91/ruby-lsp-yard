# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ruby_lsp/internal"
require "ruby_lsp_yard/inference"
require "ruby_lsp_yard/signature_store"

module BenchmarkSupport
  FIXTURE_DIR = File.expand_path("../test/fixtures/project/lib", __dir__)
  FIXTURE_FILES = %w[animals nested documented directives inheritance inference].freeze
  ITERATIONS = Integer(ENV.fetch("BENCHMARK_ITERATIONS", "500"))
  WARMUP = 50

  module_function

  def index
    @index ||= begin
      index = RubyIndexer::Index.new
      FIXTURE_FILES.each { |name| index.index_file(URI::Generic.from_path(path: File.join(FIXTURE_DIR, "#{name}.rb"))) }
      require "rbs"
      RubyIndexer::RBSIndexer.new(index).index_ruby_core
      index
    end
  end

  def context_for(source, marker)
    state = RubyLsp::GlobalState.new
    document = RubyLsp::RubyDocument.new(
      source: source,
      version: 1,
      uri: URI("file:///benchmark.rb"),
      global_state: state
    )
    offset = source.index(marker)
    raise ArgumentError, "marker not found" unless offset

    RubyLsp::RubyDocument.locate(
      document.ast,
      offset + marker.length - 1,
      node_types: [Prism::CallNode],
      code_units_cache: document.code_units_cache
    )
  end

  def measure(label, warmup: WARMUP, iterations: ITERATIONS)
    warmup.times { yield }
    samples = Array.new(iterations) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    end

    puts format(
      "%-28s p50 %6.2f ms  p95 %6.2f ms  p99 %6.2f ms",
      label,
      percentile(samples, 0.50),
      percentile(samples, 0.95),
      percentile(samples, 0.99)
    )
  end

  def percentile(samples, fraction)
    sorted = samples.sort
    sorted[[(sorted.length * fraction).ceil - 1, 0].max]
  end
end
