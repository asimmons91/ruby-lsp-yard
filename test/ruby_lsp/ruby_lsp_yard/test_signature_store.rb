# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/signature_store"

module RubyLsp
  module Yard
    class TestSignatureStore < Minitest::Test
      include IndexHelpers

      ANIMAL = "FixtureProject::Animal"
      DOG = "FixtureProject::Dog"
      DOCUMENTED = "FixtureProject::Documented"
      FACTORY = "FixtureProject::Factory"
      CHILD = "FixtureProject::ChildService"
      GRANDCHILD = "FixtureProject::GrandchildService"

      class << self
        # Core signatures are needed so `String`, `Integer` and friends resolve; the shared fixture index used by
        # the adapter contract tests stays core-free so its ancestor assertions hold.
        def core_index
          @core_index ||= begin
            helper = Object.new.extend(IndexHelpers)
            index = helper.build_fixture_index
            require "rbs"
            RubyIndexer::RBSIndexer.new(index).index_ruby_core
            index
          end
        end
      end

      def setup
        @adapter = Indexer::RubyIndexerAdapter.new(index)
        @store = SignatureStore.new(@adapter)
      end

      def index
        self.class.core_index
      end

      def test_reads_a_methods_own_docs
        signature = @store.lookup(ANIMAL, "speak")

        refute_nil signature
        assert_equal ANIMAL, signature.owner
        assert_equal "speak", signature.name
        assert_equal Types::Instance.new("String"), signature.return_types
        assert_equal [:suffix], signature.params.map(&:name)
        assert_equal [Types::Instance.new("String")], signature.params.map(&:types)
      end

      def test_finds_inherited_docs
        signature = @store.lookup(DOG, "speak")

        refute_nil signature
        assert_equal ANIMAL, signature.owner
        assert_equal [Types::Instance.new("String")], signature.params.map(&:types)
      end

      def test_matches_params_by_name_and_keeps_unmatched_tags
        signature = @store.lookup(ANIMAL, "only_one")

        assert_equal [:real], signature.params.map(&:name)
        assert_equal [Types::Instance.new("String")], signature.params.map(&:types)
        assert_equal [Documentation::RawParam.new(name: "nope", types: ["Integer"], text: "not a real parameter")],
          signature.unmatched_params
      end

      def test_matches_all_parameter_kinds
        signature = @store.lookup(ANIMAL, "signature")

        assert_equal(
          %i[required optional rest keyword keyword_optional options block],
          signature.params.map(&:name)
        )
        assert_equal(
          %i[required optional rest keyword keyword_optional keyword_rest block],
          signature.params.map(&:kind)
        )
        assert_equal Types::Instance.new("String"), signature.params.first.types
        assert Types.unknown?(signature.params[1].types)
      end

      def test_parses_union_types
        signature = @store.lookup(DOCUMENTED, "greet")

        refute_nil signature
        assert_equal Types::Union.new([Types::Instance.new("String"), Types::NIL_TYPE]),
          signature.params.find { |param| param.name == :punct }.types
      end

      def test_follows_see_references
        signature = @store.lookup(CHILD, "process")

        refute_nil signature
        assert_equal "FixtureProject::BaseService", signature.owner
        assert_equal Types::Instance.new("Integer"), signature.return_types
      end

      def test_follows_see_references_through_ancestors
        signature = @store.lookup(GRANDCHILD, "process")

        refute_nil signature
        assert_equal "FixtureProject::BaseService", signature.owner
      end

      def test_returns_self_special
        assert_equal Types::SELF, @store.lookup(DOCUMENTED, "chain").return_types
      end

      def test_reads_attribute_comments
        signature = @store.lookup(DOCUMENTED, "title")

        refute_nil signature
        assert_equal :attribute, signature.kind
        assert_equal Types::Instance.new("String"), signature.return_types
      end

      def test_attribute_conventions_apply_to_all_names
        first = @store.lookup(DOCUMENTED, "first")
        last = @store.lookup(DOCUMENTED, "last")

        assert_equal Types::Instance.new("String"), first.return_types
        assert_equal Types::Instance.new("String"), last.return_types
      end

      def test_matches_params_tagged_with_sigils
        signature = @store.lookup(DOCUMENTED, "splats")

        assert_equal [:first, :rest, :options], signature.params.map(&:name)
        assert_equal(
          [Types::Instance.new("String"), Types::Instance.new("Integer"), Types::Instance.new("Hash")],
          signature.params.map(&:types)
        )
      end

      def test_reads_raise_deprecated_and_option_tags
        signature = @store.lookup(DOCUMENTED, "fetch")

        assert signature.deprecated?
        assert_equal [Types::Instance.new("KeyError")], signature.raises.map(&:first)
        assert_equal [":strict"], signature.options.map(&:key)
        assert_includes signature.to_markdown, "Deprecated:"
        assert_includes signature.to_markdown, "**Raises:** `KeyError`"
        assert_includes signature.to_markdown, "**Option:** `:strict` (`Boolean`)"
      end

      def test_builds_overloads
        signature = @store.lookup(DOCUMENTED, "find")

        assert_equal 2, signature.overloads.size
        first = signature.overloads.first
        assert_equal [:key], first.params.map(&:name)
        assert_equal Types::Instance.new("String"), first.return_types
        assert_equal [:key, :default], signature.overloads.last.params.map(&:name)
        assert_includes signature.to_markdown, "def find(key: Symbol) → String"
      end

      def test_directives_from_a_class_comment
        signature = @store.lookup(FACTORY, "build")

        refute_nil signature
        assert_equal FACTORY, signature.owner
        assert_equal Types::Instance.new("FixtureProject::Factory"), signature.return_types
        assert_equal [Types::Instance.new("String")], signature.params.map(&:types)
      end

      def test_singleton_directives
        signature = @store.lookup(FACTORY, "create", singleton: true)

        refute_nil signature
        assert signature.singleton
        assert_equal "create", signature.name
      end

      def test_attribute_directives
        reader = @store.lookup(FACTORY, "label")
        writer = @store.lookup(FACTORY, "label=")

        refute_nil reader
        refute_nil writer
        assert_equal Types::Instance.new("String"), reader.return_types
        assert_equal [Signature::Param.new(name: :value, kind: :required, types: Types::Instance.new("String"))],
          writer.params
      end

      def test_parse_directive_creates_method_and_attribute_entries
        method = @store.lookup(FACTORY, "parsed_method")
        attribute = @store.lookup(FACTORY, "parsed_attr")

        refute_nil method
        assert_equal [:value], method.params.map(&:name)
        refute_nil attribute
        assert_equal Types::Instance.new("String"), attribute.return_types
        assert_equal Types::Instance.new("String"), method.params.first.types
      end

      def test_visibility_directive_overrides_the_definition_visibility
        signature = @store.lookup(FACTORY, "setup")

        refute_nil signature
        assert_equal :private, signature.visibility
      end

      def test_returns_nil_for_unknown_methods_or_owners
        assert_nil @store.lookup(ANIMAL, "nope")
        assert_nil @store.lookup("No::Such", "speak")
        assert_nil @store.lookup(nil, "speak")
      end

      def test_memoizes_lookups
        assert_same @store.lookup(ANIMAL, "speak"), @store.lookup(ANIMAL, "speak")
      end

      def test_invalidates_on_file_change
        first = @store.lookup(ANIMAL, "speak")

        @adapter.on_change([URI("file:///tmp/foo.rb")])

        refute_same first, @store.lookup(ANIMAL, "speak")
      end

      def test_never_raises_on_broken_docs
        store = SignatureStore.new(Indexer::RubyIndexerAdapter.new(index))
        adapter = store.instance_variable_get(:@adapter)
        adapter.define_singleton_method(:method_definitions) { |*| raise "boom" }

        assert_nil store.lookup(ANIMAL, "speak")
      end
    end
  end
end
