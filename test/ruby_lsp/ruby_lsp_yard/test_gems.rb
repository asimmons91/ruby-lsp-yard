# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "ruby_lsp_yard/gems"

module RubyLsp
  module Yard
    class TestGems < Minitest::Test
      SPEC = Struct.new(:name, :version, :full_gem_path)
      KEY = ["FixtureProject::Animal", "speak", false]

      def setup
        @root = Dir.mktmpdir("ruby-lsp-yard-cache")
      end

      def teardown
        FileUtils.remove_entry(@root) if @root && File.directory?(@root)
      end

      # --- Locator -----------------------------------------------------------------------------------------------

      def test_locator_maps_paths_to_gem_identity
        locator = Gems::Locator.new(specs: [
          SPEC.new("foo", "1.2.3", "/gems/foo-1.2.3"),
          SPEC.new("bar", "2.0.0", "/gems/foo")
        ])

        assert_equal ["foo", "1.2.3"], locator.identity("/gems/foo-1.2.3/lib/foo.rb")
        assert_equal ["bar", "2.0.0"], locator.identity(URI::Generic.from_path(path: "/gems/foo/lib/bar.rb"))
        assert_nil locator.identity("/workspace/lib/thing.rb")
        assert_nil locator.identity("/gems/foo-1.2.3/core/array.rbs")
        assert_nil locator.identity(nil)
      end

      def test_locator_prefers_the_longest_matching_path
        locator = Gems::Locator.new(specs: [
          SPEC.new("parent", "1.0.0", "/gems/parent"),
          SPEC.new("child", "2.0.0", "/gems/parent/gems/child")
        ])

        assert_equal ["child", "2.0.0"], locator.identity("/gems/parent/gems/child/lib/child.rb")
      end

      def test_locator_reads_the_lock_digest
        lockfile = File.join(@root, "Gemfile.lock")
        File.write(lockfile, "GEM\n")
        locator = Gems::Locator.new(specs: [], lockfile: lockfile)

        assert_equal Digest::SHA256.hexdigest("GEM\n"), locator.lock_digest

        File.write(lockfile, "GEM\n  foo (1.0)\n")
        assert_equal Digest::SHA256.hexdigest("GEM\n  foo (1.0)\n"), Gems::Locator.new(specs: [], lockfile: lockfile).lock_digest
        assert_nil Gems::Locator.new(specs: [], lockfile: File.join(@root, "missing")).lock_digest
      end

      # --- Cache -------------------------------------------------------------------------------------------------

      def test_cache_round_trips_a_signature
        signature = build_signature
        cache = build_cache

        cache.write(["mygem", "1.0.0"], KEY, signature)
        cached = cache.read(["mygem", "1.0.0"], KEY)

        refute_nil cached
        assert_equal "FixtureProject::Animal", cached.owner
        assert_equal "speak", cached.name
        assert_equal Types::Instance.new("String"), cached.return_types
        assert_equal [Types::Instance.new("String")], cached.params.map(&:types)
        assert_equal "file:///gems/mygem-1.0.0/lib/animal.rb", cached.uri.to_s
      end

      def test_cache_misses_are_isolated_per_gem_and_key
        cache = build_cache
        cache.write(["mygem", "1.0.0"], KEY, build_signature)

        assert_nil cache.read(["mygem", "2.0.0"], KEY)
        assert_nil cache.read(["mygem", "1.0.0"], ["FixtureProject::Dog", "speak", false])
      end

      def test_cache_is_per_schema_version
        build_cache(schema: 1).write(["mygem", "1.0.0"], KEY, build_signature)

        assert_nil build_cache(schema: 2).read(["mygem", "1.0.0"], KEY)
      end

      def test_cache_invalidates_when_the_lock_digest_changes
        locator = MutableLocator.new("a")
        cache = Gems::Cache.new(root: @root, locator: locator)
        cache.write(["mygem", "1.0.0"], KEY, build_signature)

        refute_nil cache.read(["mygem", "1.0.0"], KEY)

        locator.lock_digest = "b"
        assert_nil cache.read(["mygem", "1.0.0"], KEY)

        fresh = Gems::Cache.new(root: @root, locator: locator)
        assert_nil fresh.read(["mygem", "1.0.0"], KEY)
      end

      def test_cache_ignores_corrupt_files
        build_cache.write(["mygem", "1.0.0"], KEY, build_signature)
        cache_file = Dir[File.join(@root, Gems::Cache::SCHEMA_VERSION.to_s, "*.bin")].first
        File.binwrite(cache_file, "not marshal data")

        assert_nil build_cache.read(["mygem", "1.0.0"], KEY)
      end

      def test_cache_writes_atomically
        cache = build_cache
        cache.write(["mygem", "1.0.0"], KEY, build_signature)

        assert_empty Dir[File.join(@root, "**", "*.tmp")]
      end

      def test_cache_batches_later_writes_until_flush
        cache = build_cache
        cache.write(["mygem", "1.0.0"], KEY, build_signature)

        second_key = ["FixtureProject::Dog", "speak", false]
        cache.write(["mygem", "1.0.0"], second_key, build_signature)

        fresh = Gems::Cache.new(root: @root, locator: MutableLocator.new("digest"))
        assert_nil fresh.read(["mygem", "1.0.0"], second_key)

        cache.flush

        flushed = Gems::Cache.new(root: @root, locator: MutableLocator.new("digest"))
        refute_nil flushed.read(["mygem", "1.0.0"], second_key)
      end

      def test_cache_delegates_gem_identity
        cache = Gems::Cache.new(root: @root, locator: MutableLocator.new(nil, {"/gems/foo" => ["foo", "1.0"]}))

        assert_equal ["foo", "1.0"], cache.identity("/gems/foo/lib/foo.rb")
        assert_nil cache.identity("/workspace/lib/foo.rb")
      end

      private

      def build_cache(schema: Gems::Cache::SCHEMA_VERSION, locator: nil)
        Gems::Cache.new(
          root: @root,
          locator: locator || MutableLocator.new("digest"),
          schema: schema,
          log: nil
        )
      end

      def build_signature
        Signature.new(
          owner: "FixtureProject::Animal",
          name: "speak",
          uri: URI("file:///gems/mygem-1.0.0/lib/animal.rb"),
          params: [Signature::Param.new(:suffix, :required, Types::Instance.new("String"))],
          return_types: Types::Instance.new("String"),
          documented: true
        )
      end

      # A stand-in for `Gems::Locator` so tests can change the lock digest mid-session.
      class MutableLocator
        attr_accessor :lock_digest

        def initialize(lock_digest, identities = {})
          @lock_digest = lock_digest
          @identities = identities
        end

        def identity(path)
          path = path.to_s
          @identities.find { |prefix, _| path == prefix || path.start_with?("#{prefix}/") }&.last
        end
      end
    end
  end
end
