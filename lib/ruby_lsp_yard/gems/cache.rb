# frozen_string_literal: true

require "fileutils"

require_relative "../signature"
require_relative "locator"

module RubyLsp
  module Yard
    module Gems
      # Disk cache for signatures parsed from dependency gems (FR-M3-05, D9). Each gem gets one file under
      # `~/.cache/ruby-lsp-yard/<schema>/<gem>-<version>.bin`, holding a Marshal payload of
      # `{payload_version:, lock_digest:, signatures: {[owner, name, singleton] => Signature}}`. A payload whose
      # version or lock digest no longer matches is discarded. Reads and writes never raise (NFR-R1).
      #
      # Marshal has no class allowlist on the supported Ruby versions, so the payload is trusted as user-local
      # state: it is written atomically by the add-on and only read from the user's own cache directory. The
      # payload version and lock digest are validated before any signature is handed out.
      class Cache
        # Bumped when the marshaled `Signature` shape changes (`source` was added in M5), so old payloads are
        # ignored instead of being read without the new attribute.
        SCHEMA_VERSION = 2
        PAYLOAD_VERSION = 1
        # Writes are batched: the first signature of a gem is persisted immediately, later ones at most once per
        # threshold or interval, so enriching a completion does not rewrite the payload per method.
        FLUSH_THRESHOLD = 32
        FLUSH_INTERVAL = 2.0

        def initialize(root: nil, locator: nil, schema: SCHEMA_VERSION, log: nil)
          @root = root || default_root
          @locator = locator
          @schema = schema
          @log = log
          @payloads = {}
          @dirty = {}
          @writes = 0
          @last_flush = monotonic
          @mutex = Mutex.new
        end

        def identity(uri_or_path)
          @locator&.identity(uri_or_path)
        rescue
          nil
        end

        def read(gem, key)
          payload = payload_for(gem)
          return nil unless payload

          signature = payload[:signatures][key]
          signature.is_a?(Signature) ? signature : nil
        rescue => e
          @log&.warn("Gem cache read failed: #{e.class}: #{e.message}")
          nil
        end

        def write(gem, key, signature)
          return unless signature

          @mutex.synchronize do
            payload = payload_for_locked(gem)
            first = payload[:signatures].empty?
            payload[:signatures][key] = signature
            @dirty[gem_key(gem)] = gem
            @writes += 1

            flush_locked if first || @writes >= FLUSH_THRESHOLD || (monotonic - @last_flush) >= FLUSH_INTERVAL
          end
          nil
        rescue => e
          @log&.warn("Gem cache write failed: #{e.class}: #{e.message}")
          nil
        end

        # Persists every pending payload. Called on deactivate so a session's last writes are not lost.
        def flush
          @mutex.synchronize { flush_locked }
          nil
        end

        # Workspace files changed: the in-memory view is dropped. Pending writes are persisted first. A changed
        # Gemfile.lock invalidates the on-disk payload through {#lock_digest} the next time it is read.
        def invalidate
          @mutex.synchronize do
            flush_locked
            @payloads.clear
            @dirty.clear
          end
          nil
        end

        private

        def payload_for(gem)
          @mutex.synchronize { payload_for_locked(gem) }
        end

        def payload_for_locked(gem)
          key = gem_key(gem)
          payload = @payloads[key] ||= load_payload(gem)
          return payload if payload[:lock_digest] == lock_digest

          # FR-M3-05: a changed Gemfile.lock invalidates the cached signatures.
          @payloads[key] = {lock_digest: lock_digest, signatures: {}}
        end

        def load_payload(gem)
          path = file_for(gem)
          empty = {lock_digest: lock_digest, signatures: {}}
          return empty unless File.file?(path)

          payload = Marshal.load(File.binread(path), freeze: true)
          return empty unless payload.is_a?(Hash) && payload[:signatures].is_a?(Hash)
          return empty unless payload[:payload_version] == PAYLOAD_VERSION
          return empty unless payload[:lock_digest] == lock_digest

          {lock_digest: payload[:lock_digest], signatures: payload[:signatures].dup}
        rescue => e
          @log&.warn("Ignoring corrupt gem cache #{path}: #{e.class}: #{e.message}")
          {lock_digest: lock_digest, signatures: {}}
        end

        def flush_locked
          @dirty.each do |key, gem|
            payload = @payloads[key]
            persist(gem, payload) if payload
          end
          @dirty.clear
          @writes = 0
          @last_flush = monotonic
        rescue => e
          @log&.warn("Gem cache flush failed: #{e.class}: #{e.message}")
        end

        def persist(gem, payload)
          path = file_for(gem)
          directory = File.dirname(path)
          FileUtils.mkdir_p(directory)

          data = Marshal.dump(payload_version: PAYLOAD_VERSION, lock_digest: lock_digest, signatures: payload[:signatures])
          temporary = File.join(directory, ".#{File.basename(path)}.#{Process.pid}.tmp")
          File.binwrite(temporary, data)
          File.rename(temporary, path)
        rescue => e
          @log&.warn("Gem cache persist failed: #{e.class}: #{e.message}")
        ensure
          begin
            File.delete(temporary) if temporary && File.exist?(temporary)
          rescue
            nil
          end
        end

        def file_for(gem)
          name, version = Array(gem)
          File.join(@root, @schema.to_s, "#{sanitize(name)}-#{sanitize(version)}.bin")
        end

        def gem_key(gem)
          Array(gem).join("-")
        end

        def sanitize(value)
          value.to_s.gsub(/[^A-Za-z0-9_.-]/, "_")
        end

        def lock_digest
          @locator&.lock_digest
        end

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def default_root
          File.join(Dir.home, ".cache", "ruby-lsp-yard")
        rescue
          File.join(Dir.tmpdir, "ruby-lsp-yard")
        end
      end
    end
  end
end
