# frozen_string_literal: true

module FixtureProject
  # @return [String]
  DEFAULT_NAME = "unknown"

  module Greetable
    # @return [String]
    def greet
      "hello"
    end
  end

  # @!method self.build(name)
  #   @param name [String] the animal name
  #   @return [Animal]
  class Animal
    include Greetable

    # @return [String]
    attr_reader :name

    # @return [Integer]
    attr_accessor :age

    # @param name [String]
    def initialize(name)
      @name = name
    end

    # @param required [String]
    def signature(required, optional = 1, *rest, keyword:, keyword_optional: 2, **options, &block)
      [required, optional, rest, keyword, keyword_optional, options, block]
    end

    # @param suffix [String]
    # @return [String]
    def speak(suffix)
      "#{name}#{suffix}"
    end

    # @param real [String]
    # @param nope [Integer] not a real parameter
    # @return [nil]
    def only_one(real)
      real
    end

    private

    # @return [Symbol]
    def secret
      :secret
    end
  end

  class Dog < Animal
    # @return [String]
    def bark
      "woof"
    end

    # @return [String]
    def self.species
      "Canis familiaris"
    end
  end
end
