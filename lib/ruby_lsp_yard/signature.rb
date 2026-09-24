# frozen_string_literal: true

require_relative "types"

module RubyLsp
  module Yard
    # A method or attribute signature assembled from YARD tags. Types are instances of the {Types} model.
    class Signature
      # A single parameter: `kind` matches {Indexer::Parameter}. `types` defaults to {Types::UNKNOWN} when the
      # parameter is undocumented.
      Param = Struct.new(:name, :kind, :types, :description) do
        def typed?
          !Types.unknown?(types)
        end
      end

      # An `@option` tag with its type expression parsed against the documented definition.
      Option = Struct.new(:name, :key, :types, :default, :description)

      attr_accessor :owner, :name, :singleton, :kind, :visibility, :uri, :location,
        :summary, :params, :return_types, :overloads, :raises, :deprecated,
        :metadata, :yields, :yield_params, :yield_returns, :unmatched_params,
        :reference, :signature_text, :documented, :options

      def initialize(
        owner: nil,
        name: nil,
        singleton: false,
        kind: :method,
        visibility: :public,
        uri: nil,
        location: nil,
        summary: "",
        params: [],
        return_types: Types::UNKNOWN,
        overloads: [],
        raises: [],
        deprecated: nil,
        metadata: [],
        yields: [],
        yield_params: [],
        yield_returns: [],
        unmatched_params: [],
        reference: nil,
        signature_text: nil,
        documented: true,
        options: []
      )
        @owner = owner
        @name = name
        @singleton = singleton
        @kind = kind
        @visibility = visibility
        @uri = uri
        @location = location
        @summary = summary
        @params = params
        @return_types = return_types
        @overloads = overloads
        @raises = raises
        @deprecated = deprecated
        @metadata = metadata
        @yields = yields
        @yield_params = yield_params
        @yield_returns = yield_returns
        @unmatched_params = unmatched_params
        @reference = reference
        @signature_text = signature_text
        @documented = documented
        @options = options
      end

      def deprecated?
        !@deprecated.nil?
      end

      def documented?
        @documented
      end

      # Whether the signature carries type information worth showing on hover without repeating Ruby LSP's raw
      # docstring output (D13).
      def typed?
        !Types.unknown?(@return_types) ||
          @params.any?(&:typed?) ||
          @overloads.any?(&:typed?)
      end

      # Whether the signature carries structured information worth showing on hover without repeating Ruby LSP's
      # raw docstring output (D13).
      def renderable?
        typed? || deprecated? || @raises.any? || @options.any?
      end

      # The one-line signature shown on hover, e.g. `def fetch(key: Symbol, default: String?) → String`.
      def signature_line
        "#{definition_prefix}(#{@params.map { |param| display_param(param) }.join(", ")})#{return_suffix}"
      end

      def to_markdown
        lines = ["```ruby"]
        if @overloads.any?
          @overloads.each { |overload| lines << overload.display_line }
        else
          lines << signature_line
        end
        lines << "```"
        lines << "**Deprecated:** #{@deprecated}" if deprecated?
        @raises.each { |types, text| lines << raise_line(types, text) }
        @yields.each { |yield_tag| lines << "**Yields:** #{yield_tag.text}" unless yield_tag.text.to_s.empty? }
        @yield_params.each do |param|
          type = Types.unknown?(param.types) ? "" : " (`#{Types::Formatter.format(param.types)}`)"
          lines << "**Yields:** `#{param.name}`#{type}#{" — #{param.text}" unless param.text.to_s.empty?}"
        end
        @yield_returns.each do |yield_return|
          next if yield_return.types.empty?

          lines << "**Yields:** `#{Types::Formatter.format(Types.union(yield_return.types))}` (return)"
        end
        @options.each do |option|
          types = Types.unknown?(option.types) ? "" : " (`#{Types::Formatter.format(option.types)}`)"
          text = option.description.to_s.empty? ? "" : " — #{option.description}"
          lines << "**Option:** `#{option.key || option.name}`#{types}#{text}"
        end
        @metadata.each do |metadata|
          line = metadata_line(metadata)
          lines << line if line
        end
        lines.join("\n")
      end

      # Overloads built from a YARD signature string may not have parsed parameters, in which case the raw
      # signature text is rendered.
      def display_line
        return "def #{@signature_text}" if @params.empty? && @signature_text

        signature_line
      end

      private

      def definition_prefix
        @singleton ? "def self.#{@name}" : "def #{@name}"
      end

      def return_suffix
        Types.unknown?(@return_types) ? "" : " → #{Types::Formatter.format(@return_types)}"
      end

      def display_param(param)
        decorated = decorated_name(param)
        return decorated if Types.unknown?(param.types)

        "#{decorated}: #{Types::Formatter.format(param.types)}"
      end

      def decorated_name(param)
        case param.kind
        when :optional then "#{param.name} = ..."
        when :keyword then "#{param.name}:"
        when :keyword_optional then "#{param.name}: ..."
        when :rest then "*#{param.name}"
        when :keyword_rest then "**#{param.name}"
        when :block then "&#{param.name}"
        when :forwarding then "..."
        else param.name.to_s
        end
      end

      def raise_line(types, text)
        formatted = Types.unknown?(types) ? "" : " `#{Types::Formatter.format(types)}`"
        "**Raises:**#{formatted}#{" — #{text}" unless text.to_s.empty?}"
      end

      def metadata_line(metadata)
        text = metadata.text.to_s.strip
        case metadata.tag
        when "note" then "**Note:** #{text}"
        when "see" then "**See:** #{[metadata.name, text].compact.reject(&:empty?).join(" ")}"
        when "since" then "**Since:** #{text}"
        when "api" then "**API:** #{text}"
        when "todo" then "**Todo:** #{text}"
        end
      end
    end
  end
end
