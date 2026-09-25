# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/domains"

module RubyLsp
  module Yard
    module Domains
      class TestRegistry < Minitest::Test
        include IndexHelpers

        HOST = "FixtureProject::DomainHost"

        def setup
          @adapter = Indexer.wrap(build_fixture_index)
          @registry = Registry.new(@adapter)
        end

        def test_reads_domain_directives
          domains = @registry.domains_for(HOST)

          assert_includes domains, {owner: "FixtureProject::DslHelpers", singleton: false}
          assert_includes domains, {owner: "FixtureProject::DslBase", singleton: true}
          assert_equal 2, domains.size
        end

        def test_ignores_namespaces_without_domains
          assert_empty @registry.domains_for("FixtureProject::PlainHost")
        end

        def test_global_domains_apply_everywhere
          registry = Registry.new(@adapter, global: ["FixtureProject::DslHelpers", "Class<FixtureProject::DslBase>"])

          assert_includes registry.domains_for("FixtureProject::PlainHost"),
            {owner: "FixtureProject::DslHelpers", singleton: false}
          assert_includes registry.domains_for("FixtureProject::PlainHost"),
            {owner: "FixtureProject::DslBase", singleton: true}
        end

        def test_invalidates_on_change
          refute_empty @registry.domains_for(HOST)

          @adapter.on_change([fixture_uri("project/lib/domains.rb")])

          refute_empty @registry.domains_for(HOST)
        end
      end
    end
  end
end
