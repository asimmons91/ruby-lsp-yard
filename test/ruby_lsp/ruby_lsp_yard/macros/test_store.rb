# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/macros"
require "ruby_lsp_yard/signature_store"

module RubyLsp
  module Yard
    module Macros
      class TestStore < Minitest::Test
        include IndexHelpers

        RESOURCE = "FixtureProject::Resource"
        POST = "FixtureProject::Post"
        ARCHIVED = "FixtureProject::ArchivedPost"
        TAGGED = "FixtureProject::Tagged"
        WIDGET = "FixtureProject::Widget"
        LIBRARY = "FixtureProject::MacroLibrary"
        LABELED = "FixtureProject::Labeled"
        ARTICLE = "FixtureProject::Article"

        class << self
          def core_index
            @core_index ||= Object.new.extend(IndexHelpers).build_core_index
          end
        end

        def setup
          @adapter = Indexer.wrap(self.class.core_index)
          @store = Store.new(@adapter)
        end

        def test_expands_attached_macros_at_call_sites
          entries = @store.entries_for(POST)

          title = entries["title"]
          refute_nil title
          assert_equal POST, title.owner
          assert_equal Types::Instance.new("String"), title.return_types
          assert_match(/macros\.rb/, title.uri.to_s)
          refute_nil title.location

          assert_equal Types::Instance.new("Integer"), entries["views"].return_types
        end

        def test_expands_attached_macros_on_the_defining_class
          assert_equal Types::Instance.new("String"), @store.entries_for(RESOURCE)["default_property"].return_types
        end

        def test_resolves_macros_inherited_through_extend
          tag = @store.entries_for(TAGGED)["tag"]

          refute_nil tag
          assert_equal :attribute, tag.kind
          assert_equal Types::Instance.new("String"), tag.return_types
        end

        def test_entries_are_not_generated_for_singleton_receivers
          assert_empty @store.entries_for(POST, singleton: true)
        end

        def test_singleton_macro_expansions_are_not_instance_methods
          assert_nil @store.lookup(WIDGET, "build_widget")
          refute_nil @store.lookup(WIDGET, "build_widget", singleton: true)
        end

        def test_named_macro_definitions_do_not_expand_at_the_definition_site
          store = SignatureStore.new(@adapter, macros: @store)

          assert_nil store.lookup(LIBRARY, "counter")

          counter = store.lookup(LABELED, "counter")
          refute_nil counter
          assert_equal Types::Instance.new("Integer"), counter.return_types
        end

        def test_expands_named_macros_inside_attached_macro_data
          entries = @store.entries_for(ARTICLE)

          slug = entries["slug"]
          refute_nil slug
          assert_equal Types::Instance.new("String"), slug.return_types

          created_at = entries["created_at"]
          refute_nil created_at
          assert_equal Types::Instance.new("Time"), created_at.return_types
        end

        def test_expands_named_macro_invocations
          expanded = @store.expand_comments("@macro returnself", method_name: "duplicate")

          assert_includes expanded, "@return [self] returns itself"
        end

        def test_expands_repeated_named_macro_invocations
          expanded = @store.expand_comments("@macro returnself\nmiddle\n@macro returnself", method_name: "duplicate")

          assert_equal 2, expanded.scan("@return [self] returns itself").size
          assert_includes expanded, "middle"
        end

        def test_cycles_terminate
          expanded = @store.expand_comments("@macro cycle_a", method_name: "entry")

          assert_includes expanded, "@macro"
        end

        def test_unknown_macros_are_left_alone
          assert_equal "@macro nope", @store.expand_comments("@macro nope", method_name: "x")
        end

        def test_signature_store_uses_macro_definitions_and_expansions
          store = SignatureStore.new(@adapter, macros: @store)

          title = store.lookup(POST, "title")
          refute_nil title
          assert_equal Types::Instance.new("String"), title.return_types

          duplicate = store.lookup(POST, "duplicate")
          refute_nil duplicate
          assert_equal Types::SELF, duplicate.return_types
        end

        def test_signature_store_inherits_macro_generated_methods
          store = SignatureStore.new(@adapter, macros: @store)

          signature = store.lookup(ARCHIVED, "title")

          refute_nil signature
          assert_equal Types::Instance.new("String"), signature.return_types
        end

        def test_invalidating_drops_cached_entries
          refute_empty @store.entries_for(POST)

          @adapter.on_change([fixture_uri("project/lib/macros.rb")])

          assert_empty @store.instance_variable_get(:@entries)
        end
      end
    end
  end
end
