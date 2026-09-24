# frozen_string_literal: true

module RubyLsp
  module Yard
    module Diagnostics
      # A rule finding before it is converted to an `Interface::Diagnostic`. `target` keeps the owning definition so
      # the linter can apply `# yard:disable` suppression (FR-M5-02) and the quick fixes can find the affected tag
      # (FR-M5-03). `data` carries rule-specific payloads the fixes need, e.g. the parameter or type name.
      class Diagnostic
        attr_reader :rule, :message, :range, :target, :data

        def initialize(rule:, message:, range:, target:, data: {})
          @rule = rule
          @message = message
          @range = range
          @target = target
          @data = data
        end
      end
    end
  end
end
