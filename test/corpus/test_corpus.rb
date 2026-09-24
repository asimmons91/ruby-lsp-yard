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

      # NFR-R1: the diagnostics scanner and rules must survive every construct in the corpus without raising or
      # hanging, including the malformed-input fixture.
      def test_diagnostics_do_not_raise_on_the_corpus
        paths = Dir[File.join(CORPUS_PATH, "*.rb")]

        refute_empty paths
        paths.each do |path|
          source = File.read(path)
          uri = URI::Generic.from_path(path: path)
          document = RubyLsp::RubyDocument.new(
            source: source,
            version: 1,
            uri: uri,
            global_state: RubyLsp::GlobalState.new
          )
          linter = RubyLsp::Yard::Diagnostics::Linter.new(
            settings: RubyLsp::Yard::Settings.new(
              "diagnosticRules" => {
                "YARD/MissingParam" => "warning",
                "YARD/MissingReturn" => "warning",
                "YARD/ReturnTypeMismatch" => "warning",
                "YARD/ArgumentTypeMismatch" => "warning"
              }
            )
          )

          assert_instance_of Array, linter.run_diagnostic(uri, document), path
        end
      end
    end
  end
end
