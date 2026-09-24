# frozen_string_literal: true

require_relative "rules/argument_type_mismatch"
require_relative "rules/duplicate_tag"
require_relative "rules/invalid_directive"
require_relative "rules/invalid_type_syntax"
require_relative "rules/missing_param"
require_relative "rules/missing_return"
require_relative "rules/return_type_mismatch"
require_relative "rules/unknown_param"
require_relative "rules/unresolved_type"
require_relative "rules/yield_without_block"

module RubyLsp
  module Yard
    module Diagnostics
      # The rule set, cheap rules first (FR-M5-01). The expensive light type checks run last so the budget can skip
      # them without losing the syntax and documentation checks.
      module Rules
        ALL = [
          InvalidTypeSyntax,
          UnresolvedType,
          UnknownParam,
          DuplicateTag,
          InvalidDirective,
          YieldWithoutBlock,
          MissingParam,
          MissingReturn,
          ReturnTypeMismatch,
          ArgumentTypeMismatch
        ].freeze
      end
    end
  end
end
