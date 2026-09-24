# frozen_string_literal: true

require_relative "../types"
require_relative "method_info"

module RubyLsp
  module Yard
    module Authoring
      # Builds a full YARD comment skeleton for an undocumented `def` (FR-M4-06): a summary placeholder, one `@param`
      # per parameter, `@yield*` tags when the method yields and `@return`. Types are prefilled from the signature
      # store when the method inherits or overrides documented documentation; otherwise the placeholders stay empty.
      class Skeleton
        def initialize(def_node:, nesting:, document:, store: nil)
          @def_node = def_node
          @nesting = Array(nesting)
          @document = document
          @store = store
        end

        def text
          signature = lookup_signature
          param_types = signature ? signature.params.to_h { |param| [param.name.to_s, param.types] } : {}

          lines = ["#{indent}# TODO: Add a summary."]
          MethodInfo.parameters(@def_node).each do |param|
            lines << "#{indent}# @param #{decorated(param)} [#{render_type(param_types[param.name])}]"
          end
          if MethodInfo.yields?(@def_node)
            lines << "#{indent}# @yield [args]"
            lines << "#{indent}# @yieldreturn [Type]"
          end
          lines << "#{indent}# @return [#{render_type(signature&.return_types)}]"
          lines.join("\n") + "\n"
        end

        # A zero-width insertion at column 0 of the `def` line: {#text} already carries the definition's indentation, so
        # inserting at the indentation column would leave the first comment line double-indented and de-indent the def.
        def edit
          position = Interface::Position.new(line: @def_node.location.start_line - 1, character: 0)
          Interface::TextEdit.new(range: Interface::Range.new(start: position, end: position), new_text: text)
        end

        private

        def lookup_signature
          return nil unless @store && !@nesting.empty?

          @store.lookup(@nesting.join("::"), @def_node.name.to_s, singleton: @def_node.receiver.is_a?(Prism::SelfNode))
        rescue
          nil
        end

        def render_type(type)
          return "Type" if type.nil? || Types.unknown?(type)

          Types::Formatter.format(type)
        end

        def decorated(param)
          case param.kind
          when :rest then "*#{param.name}"
          when :keyword_rest then "**#{param.name}"
          when :block then "&#{param.name}"
          else param.name.to_s
          end
        end

        def indent
          line = @document.source.lines[@def_node.location.start_line - 1].to_s
          line[/\A[ \t]*/].to_s
        end
      end
    end
  end
end
