# frozen_string_literal: true

module FixtureProject
  # A DSL module used through an instance domain.
  module DslHelpers
    # @return [String]
    def dsl_greet
      "hello"
    end

    # @return [Integer]
    def dsl_count
      1
    end
  end

  # A class-level DSL used through a `Class<>` domain.
  class DslBase
    # @param name [String] the name
    # @return [String]
    def self.build(name)
      name
    end
  end

  # @!domain DslHelpers
  # @!domain Class<DslBase>
  class DomainHost
    def use
      dsl_greet
    end
  end

  # A namespace without domains, used to prove they do not leak.
  class PlainHost
    def use
      dsl_
    end
  end
end
