# frozen_string_literal: true

module FixtureProject
  # Greets people.
  module Greeter
    # Greets someone by name.
    # @param name [String] the person's name
    # @param punct [String, nil] optional punctuation
    # @return [String] the greeting
    def greet(name, punct = nil)
      "Hello #{name}#{punct}"
    end
  end

  class Documented
    include Greeter

    # @return [String]
    attr_reader :title

    # @return [String]
    attr_reader :first, :last

    # @return [Integer]
    attr_accessor :count

    # @param title [String] the title
    def initialize(title)
      @title = title
      @count = 0
    end

    # @param first [String] without a sigil
    # @param *rest [Integer] with a sigil
    # @param **options [Hash] with a double sigil
    def splats(first, *rest, **options)
      [first, rest, options]
    end

    # @param key [Symbol] the key
    # @return [String]
    def required_keyword(key:)
      key.to_s
    end

    # Looks up a value.
    #
    # @param key [Symbol] lookup key
    # @param default [String, nil] fallback value
    # @param limit [Integer] how many values to return
    # @param options [Hash] extra options
    # @option options [Boolean] :strict fail when the key is missing
    # @raise [KeyError] when strict and the key is missing
    # @deprecated Use {#find} instead.
    # @example Reverse
    # @example With fallback
    #   fetch(:key, "fallback")
    # @return [Array<String>, nil] matching values
    def fetch(key, default = nil, limit: 10, **options, &block)
      yield(key) if block
      nil
    end

    # Returns itself for chaining.
    # @return [self]
    def chain
      self
    end

    # @return [String]
    def label
      "documented"
    end

    # @param item [Inferable] whose label to read
    # @return [String]
    def label_of(item)
      item.label
    end

    # Iterates values.
    #
    # @yield [value] each value
    # @yieldparam value [String] the value
    # @yieldreturn [Integer] how many values were processed
    def each_value
      yield("value")
    end

    # @!method dynamic(value)
    #   @param value [String] the dynamic value
    #   @return [Documented]
    def register
    end

    # @return [Class<Documented>]
    def self.klass
      Documented
    end

    # @overload find(key)
    #   Finds a value by key.
    #   @param key [Symbol] the key
    #   @return [String]
    # @overload find(key, default)
    #   Finds a value with a fallback.
    #   @param key [Symbol] the key
    #   @param default [String] the fallback
    #   @return [String]
    def find(key, default = nil)
      default
    end
  end
end
