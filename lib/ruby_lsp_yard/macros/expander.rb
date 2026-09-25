# frozen_string_literal: true

module RubyLsp
  module Yard
    module Macros
      # Expands YARD macro data with positional interpolation (FR-M7-01). Mirrors `YARD::CodeObjects::MacroObject.expand`:
      # `$0`, `$1`, ... address `params`; `${N-M}` (and negative indexes) interpolate ranges joined with `", "`; `$*`
      # interpolates the full call source; `\$` escapes interpolation. Pure and never raises (NFR-R1).
      class Expander
        MACRO_MATCH = /(\\)?\$(?:\{(-?\d+|\*)(-)?(-?\d+)?\}|(-?\d+|\*))/

        # `params` is `[caller_method, *arguments]`, matching YARD's `all_params`. `source` is the DSL call's source
        # line, interpolated by `$*`.
        def expand(data, params: [], source: "")
          data.to_s.gsub(MACRO_MATCH) do
            escape = Regexp.last_match(1)
            first = Regexp.last_match(2) || Regexp.last_match(5)
            last = Regexp.last_match(4)
            range = !Regexp.last_match(3).nil?

            if escape
              Regexp.last_match(0)[1..]
            elsif first == "*"
              last ? Regexp.last_match(0) : source.to_s
            else
              first_index = first.to_i
              last_index = last ? last.to_i : params.size
              last_index = first_index unless range
              slice = Array(params)[first_index..last_index]
              slice ? slice.join(", ") : ""
            end
          end
        end
      end
    end
  end
end
