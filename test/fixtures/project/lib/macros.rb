# frozen_string_literal: true

module FixtureProject
  # A DSL-style resource with an attached macro.
  class Resource
    # Defines a property.
    #
    # @param name [Symbol] the property name
    # @param type [Class] the property type
    # @!macro [attach] property
    #   @!method $1
    #     @return [$2] the value of the $1 property
    def self.property(name, type)
      nil
    end

    # @!macro [new] returnself
    #   @return [self] returns itself
    def first
      self
    end

    property :default_property, String
  end

  # Uses the DSL from the superclass.
  class Post < Resource
    property :title, String
    property :views, Integer

    # @macro returnself
    def duplicate
      self
    end
  end

  # Inherits the DSL-generated methods from Post.
  class ArchivedPost < Post
  end

  # A macro whose expansion defines a singleton method.
  class Widget
    # @!macro [attach] widget_builder
    #   @!method self.$1
    #     @return [$2]
    def self.widget_builder(name, type)
      nil
    end

    widget_builder :build_widget, String
  end

  # A canonical named macro definition (no `[new]`/`[attach]` flags).
  class MacroLibrary
    # @!macro add_counter
    #   @!attribute [r] counter
    #     @return [Integer]
    def self.add_counter
      nil
    end
  end

  # Invokes the named macro from MacroLibrary.
  class Labeled
    # @macro add_counter
    def use_counter
      nil
    end
  end

  # Provides an attached macro through `extend`.
  module Labelable
    # @!macro [attach] label
    #   @!attribute [r] $1
    #     @return [$2] the $1 label
    def label(name, type)
      nil
    end
  end

  # Uses the DSL from an extended module.
  class Tagged
    extend Labelable

    label :tag, String
  end

  # Mutually recursive macros terminate expansion instead of looping.
  class Cyclic
    # @!macro [new] cycle_a
    #   @macro cycle_b
    def first_cycle
      nil
    end

    # @!macro [new] cycle_b
    #   @macro cycle_a
    def second_cycle
      nil
    end

    # @macro cycle_a
    def entry
      nil
    end
  end
end
