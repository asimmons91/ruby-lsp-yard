# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/corpus"

module RubyLsp
  module Yard
    class TestCorpus < Minitest::Test
      CORPUS_PATH = File.expand_path("../fixtures/corpus", __dir__)

      def test_committed_corpus_parses_without_errors_or_failures
        paths = Dir[File.join(CORPUS_PATH, "*.rb")]

        refute_empty paths
        result = Corpus.new(paths).run

        assert_empty result.errors
        assert_equal 0, result.failures, result.failure_samples.inspect
        assert_operator result.type_expressions, :>, 20
        assert_equal 1.0, result.parsed_rate
      end
    end
  end
end
