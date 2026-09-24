# frozen_string_literal: true

require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/DuplicateTag (warning): a `@param` or `@return` appears twice outside an `@overload` (FR-M5-01). The
        # extractor keeps overload docs separate, so only repeated top-level tags are counted.
        class DuplicateTag < Base
          class << self
            def key
              "YARD/DuplicateTag"
            end

            def default_severity
              :warning
            end

            def check(target, context)
              return [] unless target.documented?

              diagnostics = []
              seen = {}
              target.raw_doc.params.each do |tag|
                name = normalize_name(tag.name)
                if seen[name]
                  diagnostics << diagnostic(
                    "`@param #{tag.name}` appears more than once",
                    range: context.tag_range(target, "@param #{tag.name}"),
                    target: target
                  )
                else
                  seen[name] = true
                end
              end

              if target.raw_doc.returns.size > 1
                diagnostics << diagnostic(
                  "`@return` appears more than once",
                  range: context.tag_range(target, "@return"),
                  target: target
                )
              end

              diagnostics
            end
          end
        end
      end
    end
  end
end
