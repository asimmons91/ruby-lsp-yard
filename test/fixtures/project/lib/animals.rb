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

    # @param suffix [String]
    # @return [String]
    def speak(suffix)
      "#{name}#{suffix}"
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
