# frozen_string_literal: true

# A small corpus of docstrings representative of real-world YARD usage (NFR-T3). The default suite requires every
# type expression here to parse; the opt-in `rake corpus` task runs the same parser over installed gems.
module Corpus
  # @param name [String] the name
  # @param opts [Hash{Symbol => Object}] options
  # @option opts [String] :prefix ('') prefix to apply
  # @option opts [Boolean] :strict fail on miss
  # @return [Array<String>, nil] the matches
  # @raise [ArgumentError] when the name is empty
  def find(name, opts = {})
    name
  end

  # @yieldparam record [Hash{Symbol => String}] the row
  # @yieldreturn [Boolean] whether to continue
  # @return [void]
  def each_record
    yield({})
  end

  # @overload run(*args)
  #   @param args [Array<(String, Integer)>] name and count pairs
  #   @return [void]
  # @overload run(name, count)
  #   @param name [String] the name
  #   @param count [Integer] the count
  #   @return [Integer] the total
  def run(*args)
    args
  end

  # @return [Class<String>]
  def self.klass
    String
  end

  # @param handler [#call, #call!] the callback
  # @param literals [:a, :b, 1, 1.5, "s", true, false, nil] literal types are parsed but unused for typing
  # @return [self, undefined]
  def configure(handler, literals)
    self
  end

  # @param values [Enumerable<Array<String>>] nested generics
  # @param mapping [Hash{String => Array<Integer>}] nested hash values
  # @param unknown [Missing::Thing] unresolved names are references, not errors
  # @return [(String, Integer)] tuples
  def nested(values, mapping, unknown)
    [values, mapping, unknown]
  end

  # @!method dynamic(key, default = nil)
  #   @param key [Symbol] the key
  #   @param default [Object] the fallback
  #   @return [Object]
  def register
  end

  # No YARD tags at all; ignored by the corpus scan.
  def undocumented
    nil
  end
end
