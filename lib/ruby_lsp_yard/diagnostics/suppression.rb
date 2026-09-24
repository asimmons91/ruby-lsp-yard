# frozen_string_literal: true

module RubyLsp
  module Yard
    module Diagnostics
      # FR-M5-02 (D10): `# yard:disable Rule[, Rule...]` inside a definition's comment block suppresses those rules
      # for the diagnostics attached to that definition. A bare `# yard:disable` suppresses every rule for it.
      # Comment blocks are scoped per definition; there is no file-level suppression.
      class Suppression
        DIRECTIVE = /\A\s*#\s*yard:disable\b(.*)\z/

        attr_reader :rules

        def self.parse(comment_lines)
          all = false
          rules = []

          Array(comment_lines).each do |line|
            match = DIRECTIVE.match(line.to_s)
            next unless match

            names = match[1].split(/[,\s]+/).reject(&:empty?)
            if names.empty?
              all = true
            else
              rules.concat(names)
            end
          end

          return nil if !all && rules.empty?

          new(all: all, rules: rules.uniq.freeze)
        end

        def initialize(all:, rules:)
          @all = all
          @rules = rules
        end

        def suppressed?(rule_key)
          @all || @rules.include?(rule_key.to_s)
        end
      end
    end
  end
end
