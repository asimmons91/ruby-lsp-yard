# frozen_string_literal: true

require_relative "../type_walker"
require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/InvalidTypeSyntax (error): a type expression cannot be parsed (NFR-R1). Each type string is checked on
        # its own, so one broken member of a union does not hide the others.
        class InvalidTypeSyntax < Base
          class << self
            def key
              "YARD/InvalidTypeSyntax"
            end

            def default_severity
              :error
            end

            def check(target, context)
              return [] unless target.documented?

              diagnostics = []
              parser = context.parser(target)
              TypeWalker.each_type_string(target.raw_doc) do |ref|
                parser.parse!(ref.text)
              rescue Types::ParseError => e
                diagnostics << diagnostic(
                  "Invalid type expression `#{ref.text}` in #{ref.label}: #{e.message}",
                  range: context.type_range(target, ref),
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
