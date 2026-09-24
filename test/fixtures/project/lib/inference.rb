# frozen_string_literal: true

module FixtureProject
  class Inferable
    extend Greetable

    # @return [Inferable, nil]
    def maybe_self
      self
    end

    # @return [Documented, Dog]
    def pick_any
      Documented.new
    end

    # @return [#to_s, #inspect]
    def duckish
      "duck"
    end

    # @return [Array<String>]
    def names
      []
    end

    # @return [self]
    def chain
      self
    end

    # @return [String]
    def label
      "inferable"
    end

    # @return [Documented, Inferable]
    def ambiguous
      self
    end

    # @return [Inferable, #to_s]
    def mixed
      self
    end

    # @param other [Inferable]
    # @return [Inferable]
    def echo(other)
      other
    end

    # @return [Integer]
    def count
      @count ||= 0
    end

    # @return [Documented]
    def related
      @related = Documented.new
    end
  end

  class InferableChild < Inferable
  end

  class TypedConstructor
    # @return [String] not really a TypedConstructor
    def self.new
      "constructed"
    end
  end

  class SelfConstructor
    # @return [self] the constructed instance
    def self.new
      allocate
    end
  end
end
