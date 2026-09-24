# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "ruby_lsp_yard/gems"
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
          @core_index ||= Object.new.extend(IndexHelpers).build_core_index
        end

        def rbs_source
          @rbs_source ||= IndexHelpers.rbs_source
        end
      end

      def setup
        @adapter = Indexer.wrap(index)
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

      def test_unresolved_see_references_fall_back_to_ancestors
        signature = @store.lookup("FixtureProject::BrokenReferenceService", "process")

        refute_nil signature
        assert_equal "FixtureProject::BaseService", signature.owner
        assert_equal Types::Instance.new("Integer"), signature.return_types
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

      def test_renders_typed_keyword_params_with_a_single_colon
        signature = @store.lookup(DOCUMENTED, "required_keyword")

        assert_equal "def required_keyword(key: Symbol) → String", signature.signature_line
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

      def test_renders_yield_tags
        signature = @store.lookup(DOCUMENTED, "each_value")

        refute_nil signature
        assert signature.renderable?
        markdown = signature.to_markdown
        assert_includes markdown, "**Yields:** each value"
        assert_includes markdown, "**Yields:** `value` (`String`) — the value"
        assert_includes markdown, "**Yields:** `Integer` (return)"
      end

      def test_renders_example_tags
        signature = @store.lookup(DOCUMENTED, "fetch")

        markdown = signature.to_markdown
        assert_includes markdown, "**Example:** Reverse"
        assert_includes markdown, "**Example:** With fallback"
        assert_includes markdown, "```ruby\nfetch(:key, \"fallback\")\n```"
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

      def test_visibility_overrides_are_found_through_subclasses
        store = SignatureStore.new(Indexer.wrap(index))

        signature = store.lookup("FixtureProject::FactoryChild", "setup")

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
        store = SignatureStore.new(Indexer.wrap(index))
        adapter = store.instance_variable_get(:@adapter)
        adapter.define_singleton_method(:method_definitions) { |*| raise "boom" }

        assert_nil store.lookup(ANIMAL, "speak")
      end

      # --- M3: RBS integration and gem caching --------------------------------------------------------------------

      def test_rbs_is_preferred_for_core_owners
        store = rbs_store

        signature = store.lookup("String", "split")

        refute_nil signature
        assert_equal Types::Instance.new("Array", [Types::Instance.new("String")]), signature.return_types
        assert_equal [:pattern, :limit], signature.params.map(&:name)
        assert_equal [:E], store.lookup("Array", "first").type_params
      end

      def test_rbs_answers_for_core_ancestors_of_workspace_owners
        signature = rbs_store.lookup(ANIMAL, "to_s")

        refute_nil signature
        assert_equal Types::Instance.new("String"), signature.return_types
      end

      def test_yard_still_wins_for_workspace_owners
        signature = rbs_store.lookup(ANIMAL, "speak")

        refute_nil signature
        assert_equal ANIMAL, signature.owner
        assert_equal Types::Instance.new("String"), signature.return_types
      end

      def test_rbs_signatures_replace_fallbacks_once_the_environment_is_ready
        source = FakeRbsSource.new
        store = SignatureStore.new(Indexer.wrap(index), rbs: source)

        before = store.lookup("String", "split")

        refute_nil before
        assert Types.unknown?(before.return_types)

        source.become_ready
        after = store.lookup("String", "split")

        refute_same before, after
        assert_equal Types::Instance.new("Array", [Types::Instance.new("String")]), after.return_types
      end

      def test_gem_backed_signatures_are_persisted_to_the_disk_cache
        root = Dir.mktmpdir("ruby-lsp-yard-store")
        locator = FixtureGemLocator.new(IndexHelpers::FIXTURES_PATH)
        store = SignatureStore.new(Indexer.wrap(index), gem_cache: Gems::Cache.new(root: root, locator: locator))

        refute_nil store.lookup(ANIMAL, "speak")

        cached = Gems::Cache.new(root: root, locator: locator).read(["fixturegem", "1.0.0"], [ANIMAL, "speak", false])

        refute_nil cached
        assert_equal Types::Instance.new("String"), cached.return_types
        assert_equal [Types::Instance.new("String")], cached.params.map(&:types)
      ensure
        FileUtils.remove_entry(root) if root && File.directory?(root)
      end

      private

      def rbs_store
        SignatureStore.new(Indexer.wrap(index), rbs: self.class.rbs_source)
      end

      # A deferrable RBS source so tests can fill the store before the environment is ready.
      class FakeRbsSource
        def initialize
          @ready = false
          @subscribers = []
        end

        def subscribe(&block)
          @subscribers << block
          block.call if @ready
          block
        end

        def ready?
          @ready
        end

        def lookup(owner, name, singleton: false)
          return nil unless @ready && owner == "String" && name == "split"

          Signature.new(
            owner: "String",
            name: "split",
            return_types: Types::Instance.new("Array", [Types::Instance.new("String")]),
            documented: true
          )
        end

        def become_ready
          @ready = true
          @subscribers.each(&:call)
        end
      end

      # Claims the whole fixture directory belongs to one gem so the store's disk cache path is exercised.
      class FixtureGemLocator
        def initialize(root)
          @root = root
        end

        def identity(uri_or_path)
          path = uri_or_path.respond_to?(:path) ? uri_or_path.path : uri_or_path.to_s
          path.start_with?(@root) ? ["fixturegem", "1.0.0"] : nil
        end

        def lock_digest
          nil
        end
      end
    end
  end
end
