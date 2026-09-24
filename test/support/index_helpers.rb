# frozen_string_literal: true

require "prism"

begin
  require "ruby_indexer/ruby_indexer"
rescue LoadError
  # Ruby LSP 0.27 replaced RubyIndexer with Rubydex (FR-M6-01).
end

# Builds host indexes from the committed fixture project. Fixture files must exist on disk because both backends read
# comments and locations from the files. Everything here is backend neutral (FR-M6-04): on 0.26 the returned object is
# a `RubyIndexer::Index`, on 0.27 a `Rubydex::Graph`.
module IndexHelpers
  FIXTURES_PATH = File.expand_path("../fixtures", __dir__)

  # A synchronously loaded RBS source shared by every test that needs core/stdlib signatures (M3). The environment
  # is loaded once per process.
  def self.rbs_source
    @rbs_source ||= begin
      require "ruby_lsp_yard/rbs"
      loader = RubyLsp::Yard::Rbs::Loader.new(background: false)
      loader.start
      RubyLsp::Yard::Rbs::Source.new(loader)
    end
  end

  # The Rubydex backend is active when Ruby LSP 0.27 loaded Rubydex and the version-gated adapter was defined.
  def self.rubydex?
    defined?(::Rubydex::Graph) && defined?(::RubyLsp::Yard::Indexer::RubydexAdapter)
  end

  # The core RBS definitions the host indexes in a real session. Indexed directly instead of the whole workspace
  # (which would also pull in every bundled gem) to keep the test suite fast.
  def self.rbs_core_paths
    [File.join(Gem::Specification.find_by_name("rbs").full_gem_path, "core")]
  end

  FIXTURE_FILES = %w[
    project/lib/animals.rb
    project/lib/attributes.rb
    project/lib/nested.rb
    project/lib/documented.rb
    project/lib/directives.rb
    project/lib/inheritance.rb
    project/lib/inference.rb
  ].freeze

  def rubydex?
    IndexHelpers.rubydex?
  end

  def build_fixture_index
    if rubydex?
      graph = Rubydex::Graph.new
      graph.index_all(fixture_paths)
      graph.resolve
      graph
    else
      index = RubyIndexer::Index.new
      FIXTURE_FILES.each { |file| index.index_file(fixture_uri(file)) }
      index
    end
  end

  # The fixture index plus Ruby core, so names like `String` and `Array` resolve and their methods are available.
  def build_core_index
    if rubydex?
      graph = build_fixture_index
      graph.index_all(IndexHelpers.rbs_core_paths)
      graph.resolve
      graph
    else
      index = build_fixture_index
      require "rbs"
      RubyIndexer::RBSIndexer.new(index).index_ruby_core
      index
    end
  end

  # Adds an in-memory source to a host index, replacing any previous version of the same URI.
  def index_source(index, uri, source)
    if rubydex?
      index.delete_document(uri.to_s)
      index.index_source(uri.to_s, source, "ruby")
      index.resolve
    else
      index.delete(uri)
      index.index_single(uri, source)
    end
  end

  def fixture_uri(relative_path)
    URI::Generic.from_path(path: fixture_path(relative_path))
  end

  def fixture_path(relative_path)
    File.join(FIXTURES_PATH, relative_path)
  end

  def fixture_paths
    FIXTURE_FILES.map { |file| fixture_path(file) }
  end
end
