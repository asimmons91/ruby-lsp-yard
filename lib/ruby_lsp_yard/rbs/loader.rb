# frozen_string_literal: true

require "pathname"
require "rbs"
require "yaml"

module RubyLsp
  module Yard
    module Rbs
      # Builds the RBS environment for core, stdlib and (when the project has one) `rbs collection` signatures
      # (FR-M3-01, FR-M3-07) off the request path. The load runs in a background thread by default (NFR-P1) and can
      # be cancelled on deactivate. Failures leave the bridge not ready: callers fall back to YARD and the host index
      # (NFR-R1).
      class Loader
        def initialize(log: nil, background: true, workspace_path: nil)
          @log = log
          @background = background
          @workspace_path = workspace_path
          @thread = nil
          @environment = nil
          @builder = nil
          @subscribers = []
          @mutex = Mutex.new
          @cancelled = false
        end

        # Registers a callback invoked once the environment is published, so caches filled while the load was in
        # flight can be dropped. The callback runs immediately when the environment is already ready.
        def subscribe(&block)
          call_now = false
          @mutex.synchronize do
            @subscribers << block
            call_now = !@environment.nil?
          end
          block.call if call_now
          block
        end

        # Starts loading. With `background: false` (tests) the load happens inline.
        def start
          return if @thread

          if @background
            @thread = Thread.new { load }
            @thread.name = "ruby-lsp-yard-rbs" if @thread.respond_to?(:name=)
          else
            load
          end
          nil
        end

        # NFR-P1: the environment is abandoned rather than joined, so deactivate never blocks.
        def cancel
          @cancelled = true
          @thread = nil
          nil
        end

        def ready?
          !environment.nil?
        end

        def environment
          @mutex.synchronize { @environment }
        end

        def builder
          @mutex.synchronize { @builder }
        end

        def load
          environment = build_environment
          return if environment.nil? || @cancelled

          builder = ::RBS::DefinitionBuilder.new(env: environment)
          subscribers = nil
          @mutex.synchronize do
            @environment = environment
            @builder = builder
            subscribers = @subscribers.dup
          end
          @log&.debug("RBS environment ready (#{environment.class_decls.size} classes)")
          subscribers.each do |subscriber|
            subscriber.call
          rescue => e
            @log&.warn("RBS ready subscriber failed: #{e.class}: #{e.message}")
          end
        rescue => e
          @log&.error("RBS environment load failed: #{e.class}: #{e.message}")
        end

        private

        # NFR-R1: each rung drops one input (first the collection, then stdlib, then both) so a broken collection cannot
        # take core/stdlib signatures down with it; `Environment.from_loader` parses collection files eagerly and can
        # fail after `add_collection` has already succeeded.
        def build_environment
          libraries = each_library
          last_error = nil

          [[libraries, true], [libraries, false], [[], true], [[], false]].each do |libs, collection|
            return build_from(libs, collection: collection)
          rescue => e
            last_error = e
            @log&.warn("RBS environment build failed (#{e.class}: #{e.message})")
          end

          @log&.error("RBS core environment failed: #{last_error.class}: #{last_error.message}")
          nil
        end

        def build_from(libraries, collection: true)
          loader = ::RBS::EnvironmentLoader.new
          libraries.each do |library|
            loader.add(library: library) if loader.has_library?(library: library, version: nil)
          rescue ::RBS::EnvironmentLoader::UnknownLibraryError
            nil
          end
          add_collection(loader) if collection
          ::RBS::Environment.from_loader(loader).resolve_type_names
        end

        # FR-M3-07: when the project has an `rbs collection`, its locked signatures join the same environment, so
        # collection RBS wins over YARD exactly like core RBS (D5). A missing or broken collection is ignored.
        def add_collection(loader)
          config_path = collection_config_path
          return unless config_path

          lockfile_path = ::RBS::Collection::Config.to_lockfile_path(config_path)
          return unless lockfile_path.file?

          data = YAML.load_file(lockfile_path.to_s)
          lockfile = ::RBS::Collection::Config::Lockfile.from_lockfile(lockfile_path: lockfile_path, data: data)
          loader.add_collection(lockfile)
          @log&.debug("Loaded rbs collection from #{config_path}")
        rescue => e
          @log&.warn("rbs collection could not be loaded (#{e.class}: #{e.message})")
        end

        # `rbs_collection.yaml` is searched from the workspace root upward, like `rbs` itself does from the cwd.
        def collection_config_path
          return nil if @workspace_path.nil?

          path = Pathname.new(@workspace_path.to_s)
          loop do
            candidate = path + ::RBS::Collection::Config::PATH
            return candidate if candidate.file?

            parent = path.parent
            break if parent == path

            path = parent
          end
          nil
        rescue
          nil
        end

        # Every stdlib library shipped with the `rbs` gem. A library that cannot be loaded is skipped instead of
        # taking the whole environment down with it.
        def each_library
          root = ::RBS::EnvironmentLoader.new.repository.dirs.first
          return [] unless root&.directory?

          Dir.children(root).sort
        rescue => e
          @log&.warn("RBS stdlib discovery failed: #{e.class}: #{e.message}")
          []
        end
      end
    end
  end
end
