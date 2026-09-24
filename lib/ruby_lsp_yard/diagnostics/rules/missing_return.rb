# frozen_string_literal: true

require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/MissingReturn (off by default): a public method has no `@return`. Only reported for methods that
        # already carry some YARD documentation. Constructors, attribute writers and methods documented through
        # `@overload` (which carry their own returns) are exempt.
        class MissingReturn < Base
          class << self
            def key
              "YARD/MissingReturn"
            end

            def default_severity
              :off
            end

            def check(target, context)
              return [] unless target.documented? && target.def_node?
              return [] unless documented?(target)
              return [] unless target.visibility == :public
              return [] if target.name == "initialize" || target.name.end_with?("=")
              return [] if target.raw_doc.returns.any? || target.raw_doc.overloads.any?

              [diagnostic(
                "Public method `#{target.name}` has no `@return` tag",
                range: context.range_for_location(target.location),
                target: target
              )]
            end

            private

            def documented?(target)
              target.raw_doc.tagged? || target.raw_doc.directives.any?
            end
          end
        end
      end
    end
  end
end
