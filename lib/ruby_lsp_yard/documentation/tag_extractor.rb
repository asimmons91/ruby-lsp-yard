# frozen_string_literal: true

require_relative "support"
require_relative "raw_doc"

module RubyLsp
  module Yard
    module Documentation
      # Turns comment text into a {RawDoc}: structured tags and directives, with type expressions left as strings
      # (FR-M1-01..06). Malformed input degrades to an empty {RawDoc} and never raises (NFR-R1).
      class TagExtractor
        REFERENCE = /\A\s*\(see\s+([^\s)]+)\s*\)\s*/
        METHOD_NAME = /\A(?:self\s*\.\s*)?([^\s(]+)/
        SELF_RECEIVER = /\A\s*self\s*\./
        METADATA_TAGS = %w[api note see since example todo].freeze

        def initialize(log: nil)
          @log = log
        end

        # Parses `comments` and returns a {RawDoc}. `comments` is the comment text as returned by the indexer, with
        # the `#` markers already stripped.
        def extract(comments)
          Support.load!

          content = comments.to_s
          reference = content[REFERENCE, 1]
          content = content.sub(REFERENCE, "")

          parser = ::YARD::DocstringParser.new
          parser.parse(content)

          doc = RawDoc.new(summary: parser.text.to_s.strip, reference: reference)
          parser.tags.each { |tag| add_tag(doc, tag) }
          parser.directives.each { |directive| add_directive(doc, directive) }
          doc
        rescue => e
          @log&.error("Failed to parse docstring: #{e.class}: #{e.message}")
          RawDoc.new
        end

        private

        def add_tag(doc, tag)
          # `YARD::Tags::OverloadTag#is_a?` compares against `other.class` instead of `other`, so `is_a?` cannot be
          # used here. Class comparison works for every tag type.
          return unless tag.class <= ::YARD::Tags::Tag

          case tag.tag_name.to_s
          when "param"
            doc.params << RawParam.new(name: tag.name, types: Array(tag.types), text: tag.text.to_s)
          when "return"
            doc.returns << RawReturn.new(types: Array(tag.types), text: tag.text.to_s)
          when "yield"
            doc.yields << RawYield.new(names: Array(tag.types), text: tag.text.to_s)
          when "yieldparam"
            doc.yield_params << RawParam.new(name: tag.name, types: Array(tag.types), text: tag.text.to_s)
          when "yieldreturn"
            doc.yield_returns << RawReturn.new(types: Array(tag.types), text: tag.text.to_s)
          when "option"
            add_option(doc, tag)
          when "raise"
            doc.raises << RawRaise.new(types: Array(tag.types), text: tag.text.to_s)
          when "deprecated"
            doc.deprecated = tag.text.to_s
          when "overload"
            add_overload(doc, tag)
          when *METADATA_TAGS
            doc.metadata << RawMetadata.new(
              tag: tag.tag_name.to_s,
              name: tag.name,
              types: Array(tag.types),
              text: tag.text.to_s
            )
          end
        end

        def add_option(doc, tag)
          pair = tag.pair
          doc.options << RawOption.new(
            name: tag.name,
            key: pair&.name,
            types: Array(pair&.types),
            default: pair&.defaults,
            text: pair&.text.to_s
          )
        end

        def add_overload(doc, tag)
          # `.all` is the raw nested docstring, including tags. `.to_s` would only contain the prose.
          doc.overloads << RawOverload.new(signature: tag.signature.to_s.strip, doc: extract(tag.docstring.all))
        end

        def add_directive(doc, directive)
          case directive
          when ::YARD::Tags::AttributeDirective
            doc.directives << RawDirective.new(
              kind: :attribute,
              name: directive.tag.name.to_s.strip,
              types: Array(directive.tag.types),
              doc: extract(directive.tag.text)
            )
          when ::YARD::Tags::MethodDirective
            add_method_directive(doc, directive.tag)
          when ::YARD::Tags::ParseDirective
            doc.directives << RawDirective.new(
              kind: :parse,
              types: Array(directive.tag.types),
              text: directive.tag.text.to_s
            )
          when ::YARD::Tags::VisibilityDirective
            doc.directives << RawDirective.new(kind: :visibility, text: directive.tag.text.to_s)
          end
        end

        def add_method_directive(doc, tag)
          signature = tag.name.to_s.strip
          doc.directives << RawDirective.new(
            kind: :method,
            name: signature[METHOD_NAME, 1],
            singleton: signature.match?(SELF_RECEIVER),
            doc: extract(tag.text)
          )
        end
      end
    end
  end
end
