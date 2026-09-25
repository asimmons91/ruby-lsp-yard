# frozen_string_literal: true
# rbs_inline: enabled

module FixtureProject
  # An rbs-inline annotated class.
  class InlineThing
    attr_reader :label #: String

    # @rbs (Integer times) -> String
    def repeat(times)
      "x" * times
    end

    #: () -> Integer
    def count
      0
    end

    # The YARD type here must lose to the inline RBS annotation (D5).
    # @rbs () -> Symbol
    # @return [Integer] ignored
    def typed
      :x
    end

    # @rbs visible: bool
    # @rbs return: void
    def configure(visible:)
      nil
    end
  end
end
