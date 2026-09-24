# frozen_string_literal: true

module RubyLsp
  module Yard
    module Inference
      # The result of resolving a receiver expression into indexable owners (FR-M2-09, FR-M2-10). `members` are the
      # union's class members in order; `duck_methods` are the method names of a `#a, #b` duck type; `source` records
      # whether the result came from YARD inference or from Ruby LSP's own inferrer, so listeners only narrow host
      # results when the add-on actually knows better (FR-M2-19).
      class Resolution
        Member = Struct.new(:owner, :singleton, :label)

        attr_reader :members, :duck_methods, :source

        def initialize(members: [], duck_methods: [], source: :yard)
          @members = members
          @duck_methods = duck_methods
          @source = source
        end

        def yard?
          @source == :yard
        end

        def empty?
          @members.empty? && @duck_methods.empty?
        end

        # The primary owner for single-owner consumers such as hover.
        def primary
          @members.first
        end
      end
    end
  end
end
