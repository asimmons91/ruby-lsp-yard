# frozen_string_literal: true

module FixtureProject
  class BaseService
    # Processes an input.
    # @param input [String] the input
    # @return [Integer] the length
    def process(input)
      input.length
    end
  end

  class ChildService < BaseService
    # (see BaseService#process)
    def process(input)
      super
    end
  end

  class GrandchildService < ChildService
    def process(input)
      super
    end
  end

  class BrokenReferenceService < BaseService
    # (see Missing::Thing#process)
    def process(input)
      super
    end
  end
end
