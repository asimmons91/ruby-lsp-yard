# frozen_string_literal: true

module FixtureProject
  class AttributeShapes
    # @param value [String]
    # @return [String]
    def timeout
      "timeout"
    end

    # @param value [String]
    attr_writer :timeout

    # @return [Integer]
    attr_reader :reader_only

    # @param value [String]
    attr_writer :writer_only

    alias_method :timed_out, :timeout
  end
end
