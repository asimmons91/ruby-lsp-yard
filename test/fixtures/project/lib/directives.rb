# frozen_string_literal: true

module FixtureProject
  # @!method build(name)
  #   @param name [String] the factory name
  #   @return [Factory]
  class Factory
    # @!method self.create(name)
    #   @param name [String] the name
    #   @return [Factory]
    # @!attribute [rw] label
    #   @return [String] the label
    # @param value [String] the parsed method's value
    # @return [String] the parsed method's return
    # @!parse
    #   def parsed_method(value)
    #   end
    # @!parse attr_reader :parsed_attr
    # @!visibility private
    def setup
    end
  end

  class FactoryChild < Factory
  end
end
