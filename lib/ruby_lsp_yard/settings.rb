# frozen_string_literal: true

module RubyLsp
  module Yard
    # Per-add-on settings, read from `addonSettings["Ruby LSP YARD"]` (NFR-CFG1). Defaults work with no
    # configuration at all (NFR-CFG3) and malformed input never raises (NFR-R1).
    class Settings
      FEATURES = {
        completion: "enableCompletion",
        hover: "enableHover",
        signature_help: "enableSignatureHelp",
        definition: "enableDefinition",
        inlay_hints: "enableInlayHints",
        diagnostics: "enableDiagnostics",
        authoring: "enableAuthoring",
        core_types: "enableCoreTypes"
      }.freeze

      BOOLEAN_DEFAULTS = {
        "enableCompletion" => true,
        "enableHover" => true,
        "enableSignatureHelp" => true,
        "enableDefinition" => true,
        "enableInlayHints" => false,
        "enableDiagnostics" => true,
        "enableAuthoring" => true,
        "enableCoreTypes" => true,
        "debugInference" => false
      }.freeze

      DEFAULT_LOG_LEVEL = :info
      LOG_LEVELS = %i[debug info warn error].freeze

      def initialize(raw)
        @raw = raw.is_a?(Hash) ? raw : {}
        @values = BOOLEAN_DEFAULTS.dup

        BOOLEAN_DEFAULTS.each_key do |key|
          value = fetch(key)
          @values[key] = coerce_boolean(value, BOOLEAN_DEFAULTS[key]) unless value.nil?
        end
      end

      # Whether a feature is enabled. Unknown feature names are disabled.
      def enabled?(feature)
        key = FEATURES[feature]
        return false unless key

        @values.fetch(key)
      end

      def log_level
        level = fetch("logLevel").to_s.downcase.to_sym
        LOG_LEVELS.include?(level) ? level : DEFAULT_LOG_LEVEL
      end

      # NFR-O2: log how inference reached each result, for bug reports.
      def debug_inference?
        @values.fetch("debugInference")
      end

      private

      def fetch(key)
        return @raw[key.to_sym] if @raw.key?(key.to_sym)
        return @raw[key.to_s] if @raw.key?(key.to_s)

        nil
      end

      def coerce_boolean(value, default)
        case value
        when true, 1, "true"
          true
        when false, 0, "false"
          false
        else
          default
        end
      end
    end
  end
end
