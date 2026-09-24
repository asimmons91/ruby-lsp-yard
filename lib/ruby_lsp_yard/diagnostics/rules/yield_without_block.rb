# frozen_string_literal: true

require_relative "../../authoring/method_info"
require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/YieldWithoutBlock (info): `@yield*` on a method that neither yields nor takes a block (FR-M5-01).
        # A `&block` parameter or any `yield` in the body satisfies the tags.
        class YieldWithoutBlock < Base
          class << self
            def key
              "YARD/YieldWithoutBlock"
            end

            def default_severity
              :info
            end

            def check(target, context)
              return [] unless target.documented? && target.def_node?

              tags = yield_tags(target.raw_doc)
              return [] if tags.empty?

              return [] if Authoring::MethodInfo.yields?(target.node)

              tag = tags.first
              [diagnostic(
                "`#{tag}` documents a block, but `#{target.name}` neither yields nor takes a block",
                range: context.tag_range(target, tag),
                target: target
              )]
            end

            private

            def yield_tags(raw)
              tags = []
              tags << "@yield" if raw.yields.any?
              tags << "@yieldparam #{raw.yield_params.first.name}" if raw.yield_params.any?
              tags << "@yieldreturn" if raw.yield_returns.any?
              tags
            end
          end
        end
      end
    end
  end
end
