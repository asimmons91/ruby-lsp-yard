# frozen_string_literal: true

require "stringio"

module RubyLsp
  module Yard
    module Documentation
      # Loads the `yard` gem lazily and neutralizes the parts of it that assume a `YARD::Registry` or a source
      # parser, because the add-on only uses YARD's docstring parser (D2).
      module Support
        # `@!parse` and `@!macro` execute YARD's source parser and Registry at parse time. Directives are
        # interpreted by the add-on itself from {::YARD::Tags::Directive#tag}, so their `call` becomes a no-op.
        module NoOpDirective
          def call
            self
          end
        end

        class << self
          def load!
            return if @loaded

            @loaded = true

            require "yard/logging"
            # YARD logs to STDOUT by default, which would corrupt the LSP stream (NFR-O1).
            ::YARD::Logger.instance.io = StringIO.new
            ::YARD::Logger.instance.level = ::YARD::Logger::FATAL

            require "yard"
            ::YARD::Tags::ParseDirective.prepend(NoOpDirective)
            ::YARD::Tags::MacroDirective.prepend(NoOpDirective)
          end

          def loaded?
            !!@loaded
          end
        end
      end
    end
  end
end
