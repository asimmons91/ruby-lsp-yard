# frozen_string_literal: true

require "prism"
require "ruby_indexer/ruby_indexer"

# Builds `RubyIndexer` instances from the committed fixture project. Fixture files must exist on disk because the
# indexer lazily re-parses them to retrieve comments.
module IndexHelpers
  FIXTURES_PATH = File.expand_path("../fixtures", __dir__)

  FIXTURE_FILES = %w[
    project/lib/animals.rb
    project/lib/nested.rb
  ].freeze

  def build_fixture_index
    index = RubyIndexer::Index.new
    FIXTURE_FILES.each { |file| index.index_file(fixture_uri(file)) }
    index
  end

  def fixture_uri(relative_path)
    URI::Generic.from_path(path: File.join(FIXTURES_PATH, relative_path))
  end
end
