# frozen_string_literal: true

require_relative "budget"
require_relative "context"
require_relative "rules"
require_relative "scanner"

module RubyLsp
  module Yard
    module Diagnostics
      # The `run_diagnostic` implementation Ruby LSP calls for the registered `"yard"` linter (FR-M5-01). It scans
      # the live document, runs the enabled rules within the budget (FR-M5-04), applies `# yard:disable` suppression
      # (FR-M5-02) and converts the findings. Never raises: failures return nil so the host response is unaffected
      # (NFR-R1/R2).
      class Linter
        SOURCE = "YARD"

        SEVERITIES = {
          error: Constant::DiagnosticSeverity::ERROR,
          warning: Constant::DiagnosticSeverity::WARNING,
          info: Constant::DiagnosticSeverity::INFORMATION,
          hint: Constant::DiagnosticSeverity::HINT
        }.freeze

        attr_reader :rules

        def initialize(adapter: nil, store: nil, inference: nil, settings: nil, log: nil,
          rules: Rules::ALL, budget_ms: Budget::DEFAULT_TIMEOUT_MS)
          @adapter = adapter
          @store = store
          @inference = inference
          @settings = settings
          @log = log
          @rules = rules.nil? ? Rules::ALL : Array(rules)
          @budget_ms = budget_ms
          @active = true
        end

        # FR-M4-P2/NFR-R2: after deactivate the registered linter becomes a no-op so a stale registration cannot
        # keep working against released references.
        def deactivate!
          @active = false
          @adapter = nil
          @store = nil
          @inference = nil
        end

        def active?
          @active
        end

        def run_diagnostic(uri, document)
          diagnostics = diagnostics_for(document)
          return nil unless diagnostics

          to_lsp(diagnostics)
        rescue => e
          @log&.error("Diagnostics failed for #{uri}: #{e.class}: #{e.message}")
          nil
        end

        # The internal findings for a document, or nil when the linter cannot run. The quick fixes consume these
        # directly so they can reach the affected tags (FR-M5-03).
        def diagnostics_for(document)
          return nil unless @active && diagnostics_enabled?
          return nil unless document.respond_to?(:language_id) && document.language_id == :ruby
          return nil if document.respond_to?(:syntax_error?) && document.syntax_error?

          targets = Scanner.new(document, log: @log).targets
          budget = Budget.new(timeout_ms: @budget_ms)
          context = Context.new(
            document: document,
            adapter: @adapter,
            store: @store,
            inference: @inference,
            budget: budget,
            log: @log,
            targets: targets
          )
          return collect(targets, context) unless @inference

          @inference.with_document(document) { collect(targets, context) }
        rescue => e
          @log&.error("Diagnostics failed: #{e.class}: #{e.message}")
          nil
        end

        # FR-M5-01: the configured severity for a rule, or its built-in default. `:off` disables it.
        def severity_for(rule)
          configured = @settings.respond_to?(:rule_severity) ? @settings.rule_severity(rule.key) : nil
          configured || rule.default_severity
        end

        # FR-M5-02: whether a finding is suppressed through `# yard:disable` on its definition. Document-wide rules
        # carry no target and cannot be suppressed this way.
        def suppressed?(diagnostic)
          diagnostic.target ? diagnostic.target.suppressed?(diagnostic.rule) : false
        end

        private

        def diagnostics_enabled?
          return true unless @settings.respond_to?(:enabled?)

          @settings.enabled?(:diagnostics)
        end

        def collect(targets, context)
          diagnostics = []
          @rules.each do |rule|
            severity = severity_for(rule)
            next if severity.nil? || severity == :off

            collect_rule(rule, targets, context, diagnostics)
          end
          diagnostics
        end

        # A failing rule must not take down the other rules or the host response (NFR-R1/R2). The rule's return value
        # is normalized so a single diagnostic rather than an array cannot break the request.
        def collect_rule(rule, targets, context, diagnostics)
          if rule.document_rule?
            diagnostics.concat(Array(rule.check_document(context)))
          else
            targets.each do |target|
              break unless context.budget.check!

              diagnostics.concat(Array(rule.check(target, context)))
            end
          end
        rescue => e
          @log&.error("Diagnostics rule #{rule.key} failed: #{e.class}: #{e.message}")
        end

        def to_lsp(diagnostics)
          severities = @rules.to_h { |rule| [rule.key, severity_for(rule)] }
          diagnostics.filter_map do |diagnostic|
            next if suppressed?(diagnostic)

            severity = severities[diagnostic.rule]
            next if severity.nil? || severity == :off || diagnostic.range.nil?

            Interface::Diagnostic.new(
              range: diagnostic.range,
              severity: SEVERITIES[severity],
              code: diagnostic.rule,
              source: SOURCE,
              message: diagnostic.message
            )
          end.sort_by { |item| [item.range.start.line, item.range.start.character] }
        end
      end
    end
  end
end
