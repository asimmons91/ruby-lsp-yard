# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

desc "Parse the YARD comments of the installed gems in test/corpus/gems.txt (NFR-T3)"
task :corpus do
  $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
  require "ruby_lsp_yard/corpus"

  list_path = File.expand_path("test/corpus/gems.txt", __dir__)
  names = File.readlines(list_path, chomp: true).reject { |line| line.empty? || line.start_with?("#") }

  paths = []
  missing = []
  names.each do |gem_name|
    paths.concat(Dir[File.join(Gem::Specification.find_by_name(gem_name).full_gem_path, "lib", "**", "*.rb")])
  rescue Gem::MissingSpecError
    missing << gem_name
  end

  if paths.empty?
    abort "corpus: none of the #{names.size} gems are installed. Run: gem install --no-document #{names.join(" ")}"
  end

  result = RubyLsp::Yard::Corpus.new(paths).run
  max_failure_rate = Float(ENV.fetch("CORPUS_MAX_FAILURE_RATE", "0.01"))

  puts "corpus: #{names.size - missing.size}/#{names.size} gems, #{result.files} files, " \
    "#{result.comments} documented comments"
  puts "corpus: #{result.type_expressions} type expressions, #{result.failures} failures " \
    "(parsed #{(result.parsed_rate * 100).round(2)}%, threshold #{(100 - max_failure_rate * 100).round(2)}%)"
  puts "corpus: skipped gems: #{missing.join(", ")}" if missing.any?
  result.failure_samples.each { |path, type| puts "  failed: #{type.inspect} in #{path}" }

  abort "corpus: #{result.errors.size} file errors" if result.errors.any?
  abort "corpus: failure rate above #{max_failure_rate}" if result.failure_rate > max_failure_rate
end

task default: %i[test standard]
