# frozen_string_literal: true

require "prism"

require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/InvalidDirective (error): a directive is malformed, or its `@!parse` text has a Ruby syntax error
        # (FR-M5-01). YARD silently drops unknown or misspelled directives, so the comment text is scanned directly in
        # addition to the parsed directives.
        class InvalidDirective < Base
          # Every directive YARD recognizes (`YARD::Tags::Library`), plus `domain` (Solargraph compatibility,
          # planned for M7). YARD silently drops unknown or misspelled directives, so they are found by scanning the
          # comment text.
          KNOWN = %w[attribute domain endgroup group macro method parse scope visibility].freeze
          VALID_VISIBILITIES = %w[public protected private].freeze
          DIRECTIVE = /\A@!(\w+)(.*)\z/

          class << self
            def key
              "YARD/InvalidDirective"
            end

            def default_severity
              :error
            end

            def check(target, context)
              diagnostics = []
              scan_unknown(target, context, diagnostics)
              scan_parsed(target, context, diagnostics)
              diagnostics
            end

            private

            # YARD drops directives it does not recognize or cannot parse, leaving no trace in the RawDoc.
            def scan_unknown(target, context, diagnostics)
              target.comment_lines.each do |line|
                match = DIRECTIVE.match(strip_comment_marker(line))
                next unless match

                name = match[1]
                rest = match[2].to_s.strip
                if KNOWN.include?(name)
                  diagnostics << malformed(name, context, target) if malformed?(name, rest)
                else
                  diagnostics << diagnostic(
                    "Unknown directive `@!#{name}`",
                    range: context.tag_range(target, "@!#{name}"),
                    target: target
                  )
                end
              end
            end

            def malformed?(name, rest)
              case name
              when "method"
                rest.empty? || method_signature_name(rest).empty?
              when "attribute"
                rest.sub(/\A\[[^\]]*\]\s*/, "").empty?
              when "visibility"
                !VALID_VISIBILITIES.include?(rest)
              else
                false
              end
            end

            def malformed(name, context, target)
              message = case name
              when "method" then "`@!method` is missing a method signature"
              when "attribute" then "`@!attribute` is missing an attribute name"
              else "`@!visibility` must be one of #{VALID_VISIBILITIES.join(", ")}"
              end
              diagnostic(message, range: context.tag_range(target, "@!#{name}"), target: target)
            end

            def method_signature_name(signature)
              signature[/\A(?:self\s*\.\s*)?([^\s(]+)/, 1].to_s
            end

            # `@!parse` runs its text through Prism; a syntax error is reported at the directive (FR-M5-01).
            def scan_parsed(target, context, diagnostics)
              return unless target.documented?

              target.raw_doc.directives.each do |directive|
                next unless directive.kind == :parse

                result = Prism.parse(directive.text.to_s)
                next if result.success?

                message = result.errors.first&.message.to_s
                diagnostics << diagnostic(
                  "`@!parse` text has a Ruby syntax error#{": #{message}" unless message.empty?}",
                  range: context.tag_range(target, "@!parse"),
                  target: target
                )
              end
            end

            def strip_comment_marker(line)
              line.to_s.sub(/\A\s*#\s?/, "")
            end
          end
        end
      end
    end
  end
end
