# frozen_string_literal: true

require "prism"

require_relative "documentation"
require_relative "types"

module RubyLsp
  module Yard
    # Parses the YARD comments of a set of Ruby files and reports how many type expressions fail to parse
    # (NFR-T3). This is a measurement tool: it does not run inside the language server.
    class Corpus
      class Result
        attr_reader :files, :comments, :type_expressions, :failures, :errors, :failure_samples

        def initialize(files:, comments:, type_expressions:, failures:, errors:, failure_samples:)
          @files = files
          @comments = comments
          @type_expressions = type_expressions
          @failures = failures
          @errors = errors
          @failure_samples = failure_samples
        end

        def failure_rate
          return 0.0 if @type_expressions.zero?

          @failures.to_f / @type_expressions
        end

        def parsed_rate
          1.0 - failure_rate
        end
      end

      def initialize(paths, log: nil)
        @paths = Array(paths)
        @extractor = Documentation::TagExtractor.new(log: log)
        @parser = Types::Parser.new
        @comments = 0
        @type_expressions = 0
        @failures = 0
        @errors = []
        @failure_samples = []
      end

      def run
        @paths.each { |path| scan_file(path) }

        Result.new(
          files: @paths.size,
          comments: @comments,
          type_expressions: @type_expressions,
          failures: @failures,
          errors: @errors,
          failure_samples: @failure_samples
        )
      end

      private

      def scan_file(path)
        comments = Prism.parse_file_comments(path)
        grouped = comments.slice_when { |left, right| left.location.start_line + 1 != right.location.start_line }

        grouped.each do |group|
          text = group.filter_map { |comment| comment_text(comment) }.join("\n")
          next if text.empty?

          raw = @extractor.extract(text)
          next if raw.empty?

          @comments += 1
          scan_types(path, raw)
        end
      rescue => e
        @errors << [path, "#{e.class}: #{e.message}"]
      end

      def comment_text(comment)
        content = comment.slice.chomp
        return unless content.valid_encoding?

        content.delete_prefix!("#")
        content.delete_prefix!(" ")
        content
      end

      def scan_types(path, raw)
        type_strings(raw).each do |type|
          @type_expressions += 1
          @parser.parse!(type)
        rescue Types::ParseError
          @failures += 1
          @failure_samples << [path, type] if @failure_samples.size < 20
        end
      end

      def type_strings(raw)
        strings = []
        [raw.params, raw.yield_params].each { |list| list.each { |tag| strings.concat(tag.types) } }
        [raw.returns, raw.yield_returns, raw.raises].each { |list| list.each { |tag| strings.concat(tag.types) } }
        raw.options.each { |tag| strings.concat(tag.types) }
        raw.overloads.each { |overload| strings.concat(type_strings(overload.doc)) }
        raw.directives.each { |directive| strings.concat(type_strings(directive.doc)) if directive.doc }
        strings
      end
    end
  end
end
