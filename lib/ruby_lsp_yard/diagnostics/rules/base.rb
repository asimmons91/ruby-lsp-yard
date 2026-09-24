# frozen_string_literal: true

require_relative "../diagnostic"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # Base class for a diagnostic rule (FR-M5-01). Rules are stateless: the linter passes a
        # {Diagnostics::Context} to {.check} or {.check_document}. `key` is the rule name shown to users and used in
        # `diagnosticRules` and `# yard:disable`; `default_severity` is overridden by the `diagnosticRules` setting.
        class Base
          class << self
            def key
              raise NotImplementedError
            end

            def default_severity
              raise NotImplementedError
            end

            # Per-definition rules receive each {Target} the scanner found.
            def check(_target, _context)
              []
            end

            # Document-wide rules (the light type checks) run once per document.
            def document_rule?
              false
            end

            def check_document(_context)
              []
            end

            def diagnostic(message, range:, target:, data: {})
              Diagnostic.new(rule: key, message: message, range: range, target: target, data: data)
            end

            # Matches the signature store's parameter matching (FR-M1-06): `*args`, `**opts`, `&blk` and `name:`
            # all normalize to the bare name.
            def normalize_name(name)
              name.to_s.sub(/\A[*&]+/, "").sub(/:+\z/, "")
            end
          end
        end
      end
    end
  end
end
