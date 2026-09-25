# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/documentation"
require "ruby_lsp_yard/macros"

module RubyLsp
  module Yard
    module Macros
      class TestExpander < Minitest::Test
        def expand(data, params: [], source: "")
          Expander.new.expand(data, params: params, source: source)
        end

        def test_expands_positional_parameters
          params = ["property", ":title", "String"]

          assert_equal "property", expand("$0", params: params)
          assert_equal ":title", expand("$1", params: params)
          assert_equal "String", expand("$2", params: params)
        end

        def test_expands_ranges
          params = ["create_method_with_args", ":foo", ":a", ":b", ":c", "String"]

          assert_equal ":a, :b, :c", expand("${2--2}", params: params)
          assert_equal ":foo, :a, :b", expand("${1-3}", params: params)
          assert_equal "String", expand("${-1}", params: params)
        end

        def test_expands_the_full_source
          assert_equal "property :title, String", expand("$*", source: "property :title, String")
        end

        def test_escapes_interpolation
          assert_equal "I have $2.00 USD.", expand("I have \\$2.00 USD.", params: [":title"])
        end

        def test_out_of_range_parameters_expand_to_empty
          assert_equal "", expand("$9", params: ["property"])
          assert_equal "", expand("${5-7}", params: ["property"])
        end

        def test_matches_yard_expansion
          Documentation::Support.load!
          cases = [
            ["$0 $1 $2", ["caller", ":title", "String"], "caller :title String"],
            ["${2--2}", ["caller", ":foo", ":a", ":b", ":c", "String"], ""],
            ["$*", ["caller"], "caller :title"],
            ["I have \\$2.00", ["caller", ":title"], "I have $2.00"],
            ["$9 and ${9-10}", ["caller"], " and "],
            ["@!method $1(${3-})", ["caller", ":foo", ":a"], ""]
          ]

          cases.each do |data, params, source|
            expected = ::YARD::CodeObjects::MacroObject.expand(data, params, source)
            assert_equal expected, expand(data, params: params, source: source), "for #{data.inspect}"
          end
        end
      end
    end
  end
end
