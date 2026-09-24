# frozen_string_literal: true

require_relative "model"

module RubyLsp
  module Yard
    module Types
      class ParseError < StandardError; end

      # Parses a single YARD type expression into the internal type model (FR-M1-07..09). Class names are resolved
      # through the injected `resolver` callable `(name, nesting) -> fully_qualified_name | nil`; unresolved names
      # become {Ref}s rather than errors. Parsing never raises: failures degrade to {UNKNOWN} (NFR-R1).
      class Parser
        def initialize(resolver: nil, nesting: [])
          @resolver = resolver
          @nesting = Array(nesting)
          @text = ""
          @index = 0
        end

        def parse(type_string)
          parse!(type_string)
        rescue
          UNKNOWN
        end

        # Like {#parse} but raises {ParseError} so callers can measure failures (corpus test, M5 diagnostics).
        def parse!(type_string)
          @text = type_string.to_s
          @index = 0
          result = parse_union
          skip_whitespace
          raise ParseError, "trailing input at #{@index}" unless eof?

          result
        end

        # Parses a list of type expressions (already split by YARD on top-level commas) into one union.
        def parse_list(type_strings)
          Types.union(Array(type_strings).map { |string| parse(string) })
        end

        private

        def parse_union
          types = [parse_type]
          loop do
            skip_whitespace
            break unless consume(",")

            types << parse_type
          end
          Types.union(types)
        end

        # Also accepts the `|` union notation used by some real-world docstrings (e.g. `Corrector | nil`).
        def parse_type
          union = [parse_primary]
          loop do
            skip_whitespace
            break unless consume("|")

            union << parse_primary
          end
          Types.union(union)
        end

        def parse_primary
          skip_whitespace
          raise ParseError, "unexpected end of input" if eof?

          char = current
          if char == ":" && peek(1) != ":"
            parse_symbol_literal
          elsif char == '"' || char == "'"
            Literal.new(read_string)
          elsif char == "#"
            parse_duck
          elsif char == "{"
            parse_hash_body
          elsif char == "("
            advance
            Tuple.new(parse_arguments(")"))
          elsif char == "["
            advance
            Tuple.new(parse_arguments("]"))
          elsif char == "-" && digit?(peek(1))
            advance
            number = parse_number
            Literal.new(-number.value)
          elsif digit?(char)
            parse_number
          else
            parse_named
          end
        end

        def parse_named
          name = read_constant_name
          raise ParseError, "expected a type name" if name.empty?

          skip_whitespace

          if current == "<"
            advance
            build_generic(name, parse_arguments(">"))
          elsif name == "Hash" && current == "{"
            parse_hash_body
          elsif current == "("
            advance
            arguments = parse_arguments(")")
            build_generic(name, arguments)
          else
            build_simple(name)
          end
        end

        def build_generic(name, arguments)
          if name == "Class"
            singleton_name = Types.name_of(arguments.first)
            singleton_name ? Singleton.new(singleton_name) : UNKNOWN
          elsif name == "Hash" && arguments.size == 2
            HashOf.new(arguments[0], arguments[1])
          elsif name == "Array" && arguments.size != 1
            Tuple.new(arguments)
          else
            named(name, arguments)
          end
        end

        def build_simple(name)
          case name
          when "nil" then NIL_TYPE
          when "true", "false", "Boolean" then BOOLEAN
          when "self" then SELF
          when "void" then VOID
          when "undefined", "untyped" then UNTYPED
          when "Object" then UNKNOWN
          else named(name)
          end
        end

        # Returns an `Instance` for a name that resolves against the index, or a `Ref` when it does not. Generic
        # arguments keep their owner as an `Instance` so the arguments are not lost.
        def named(name, arguments = [])
          resolved = @resolver&.call(name, @nesting)
          return Instance.new(resolved, arguments) if resolved
          return Ref.new(name) if arguments.empty?

          Instance.new(name, arguments)
        end

        def parse_hash_body
          expect("{")
          skip_whitespace
          key = parse_type
          skip_whitespace
          expect("=>")
          skip_whitespace
          value = parse_type
          skip_whitespace
          expect("}")
          HashOf.new(key, value)
        end

        def parse_symbol_literal
          expect(":")
          value = if current == '"' || current == "'"
            read_string
          else
            read_regexp(/[A-Za-z_][A-Za-z0-9_]*[=?!]?/)
          end
          raise ParseError, "empty symbol literal" if value.empty?

          Literal.new(value.to_sym)
        end

        def parse_duck
          expect("#")
          method_name = read_regexp(/[A-Za-z_][A-Za-z0-9_]*[=?!]?/)
          raise ParseError, "empty duck type" if method_name.empty?

          skip_whitespace
          skip_parenthesized_arguments if current == "("
          Duck.new([method_name])
        end

        def parse_number
          number = read_regexp(/\d+(?:\.\d+)?/)
          raise ParseError, "invalid number" if number.empty?

          Literal.new(number.include?(".") ? number.to_f : number.to_i)
        end

        def parse_arguments(close)
          arguments = []
          skip_whitespace
          if consume(close)
            return arguments
          end

          loop do
            arguments << parse_type
            skip_whitespace
            break if consume(close)

            expect(",")
          end
          arguments
        end

        def read_constant_name
          start = @index
          advance(2) if @text[@index, 2] == "::"
          read_regexp(/[A-Za-z_][A-Za-z0-9_]*/)
          while @text[@index, 2] == "::" && @text[@index + 2].to_s.match?(/[A-Za-z_]/)
            advance(2)
            read_regexp(/[A-Za-z_][A-Za-z0-9_]*/)
          end
          @text[start...@index]
        end

        def read_string
          quote = current
          advance
          buffer = +""
          closed = false
          until eof?
            char = current
            advance
            if char == "\\" && !eof?
              buffer << current
              advance
            elsif char == quote
              closed = true
              break
            else
              buffer << char
            end
          end
          raise ParseError, "unterminated string literal" unless closed

          buffer
        end

        # Duck type signatures such as `#call(Diagnostic)` carry arguments we do not model.
        def skip_parenthesized_arguments
          depth = 0
          until eof?
            char = current
            advance
            depth += 1 if char == "("
            depth -= 1 if char == ")"
            break if depth.zero?
          end
        end

        def read_regexp(regexp)
          match = /\G#{regexp}/.match(@text, @index)
          return "" unless match

          @index = match.end(0)
          match[0]
        end

        def skip_whitespace
          advance while !eof? && current =~ /\s/
        end

        def eof?
          @index >= @text.length
        end

        def current
          @text[@index]
        end

        def peek(offset)
          @text[@index + offset]
        end

        def advance(count = 1)
          @index += count
        end

        def consume(string)
          return false unless @text[@index, string.length] == string

          advance(string.length)
          true
        end

        def expect(string)
          raise ParseError, "expected #{string.inspect} at #{@index}" unless consume(string)
        end

        def digit?(char)
          char.to_s.match?(/\d/)
        end
      end
    end
  end
end
