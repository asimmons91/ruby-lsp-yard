# frozen_string_literal: true

require_relative "support"
require "ruby_lsp_yard/rbs"

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
loader = RubyLsp::Yard::Rbs::Loader.new(background: false)
loader.start
elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

puts format(
  "%-28s %6.2f ms (%d classes, %d interfaces)",
  "RBS environment (core+stdlib)",
  elapsed,
  loader.environment.class_decls.size,
  loader.environment.interface_decls.size
)

source = RubyLsp::Yard::Rbs::Source.new(loader)

BenchmarkSupport.measure("RBS lookup String#split") { source.lookup("String", "split") }
BenchmarkSupport.measure("RBS lookup Array#first") { source.lookup("Array", "first") }
BenchmarkSupport.measure("RBS lookup Hash#each") { source.lookup("Hash", "each") }

puts "budget: environment load runs in the background and must not block requests (NFR-P1)"
