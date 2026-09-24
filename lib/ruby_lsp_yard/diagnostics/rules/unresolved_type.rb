# frozen_string_literal: true

require_relative "../type_walker"
require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/UnresolvedType (warning): a type name does not resolve to a known constant (FR-M5-01). Generic type
        # parameters (`Array<T>`) and RBS interface names are not reported. Requires a working indexer adapter; when
        # the adapter or the name resolution is unavailable the rule stays silent.
        class UnresolvedType < Base
          class << self
            def key
              "YARD/UnresolvedType"
            end

            def default_severity
              :warning
            end

            def check(target, context)
              return [] unless target.documented?
              return [] unless context.resolver

              diagnostics = []
              parser = context.parser(target)
              TypeWalker.each_type_string(target.raw_doc) do |ref|
                type = parser.parse(ref.text)
                next if Types.unknown?(type)

                TypeWalker.unresolved_names(type, resolver: context.resolver, nesting: target.nesting).each do |name|
                  diagnostics << diagnostic(
                    "Type `#{name}` in #{ref.label} does not resolve to a known constant",
                    range: context.type_range(target, ref),
                    target: target,
                    data: {name: name}
                  )
                end
              end
              diagnostics
            end
          end
        end
      end
    end
  end
end
