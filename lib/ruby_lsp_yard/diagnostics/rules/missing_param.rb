# frozen_string_literal: true

require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/MissingParam (off by default): a parameter has no `@param` tag. Only reported for methods that already
        # carry some YARD documentation, so enabling the rule does not flag every undocumented method in a codebase.
        class MissingParam < Base
          class << self
            def key
              "YARD/MissingParam"
            end

            def default_severity
              :off
            end

            def check(target, context)
              return [] unless target.documented? && target.def_node?
              return [] unless documented?(target)
              return [] if target.raw_doc.overloads.any?

              tags = target.raw_doc.params.map { |tag| normalize_name(tag.name) }
              target.parameters.filter_map do |parameter|
                next if parameter.name.to_s.empty? || tags.include?(normalize_name(parameter.name))

                diagnostic(
                  "Parameter `#{parameter.name}` has no `@param` tag",
                  range: context.range_for_location(target.location),
                  target: target,
                  data: {parameter: parameter.name}
                )
              end
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
