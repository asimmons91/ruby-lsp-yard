# frozen_string_literal: true

require "rbs"

module RubyLsp
  module Yard
    module Rbs
      # Builds the RBS environment for core and stdlib signatures (FR-M3-01) off the request path. The load runs in
      # a background thread by default (NFR-P1) and can be cancelled on deactivate. Failures leave the bridge not
      # ready: callers fall back to YARD and the host index (NFR-R1).
      class Loader
        def initialize(log: nil, background: true)
          @log = log
          @background = background
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

        def build_environment
          libraries = each_library
          build_from(libraries)
        rescue => e
          @log&.warn("RBS environment with stdlib failed (#{e.class}: #{e.message}); falling back to core")
          begin
            build_from([])
          rescue => core_error
            @log&.error("RBS core environment failed: #{core_error.class}: #{core_error.message}")
            nil
          end
        end

        def build_from(libraries)
          loader = ::RBS::EnvironmentLoader.new
          libraries.each do |library|
            loader.add(library: library) if loader.has_library?(library: library, version: nil)
          rescue ::RBS::EnvironmentLoader::UnknownLibraryError
            nil
          end
          ::RBS::Environment.from_loader(loader).resolve_type_names
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
