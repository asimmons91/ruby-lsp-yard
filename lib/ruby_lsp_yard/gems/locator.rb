# frozen_string_literal: true

require "digest"
require "uri"

module RubyLsp
  module Yard
    module Gems
      # Maps a definition's file path back to the gem that provides it (FR-M3-05/06). Built from Bundler's locked
      # gems plus the running Ruby's default gems. Gems excluded from Ruby LSP's indexing never reach the store,
      # because the host index never returns their definitions, so no exclusion list is needed here.
      class Locator
        Spec = Struct.new(:name, :version, :path)

        def initialize(specs: nil, lockfile: nil)
          @specs = build_specs(specs)
          @lockfile = lockfile || default_lockfile
        end

        # `[name, version]` for a definition URI or file path, or nil for workspace files and unknown paths.
        def identity(uri_or_path)
          path = extract_path(uri_or_path)
          return nil if path.nil? || path.empty?

          path = path.to_s
          # RBS signature files carry no YARD comments and are already served by the RBS bridge.
          return nil if path.end_with?(".rbs")
          spec = @specs.find { |candidate| path == candidate.path || path.start_with?("#{candidate.path}/") }
          spec && [spec.name, spec.version]
        rescue
          nil
        end

        def lock_digest
          return @lock_digest if defined?(@lock_digest)

          @lock_digest = File.file?(@lockfile) ? Digest::SHA256.file(@lockfile).hexdigest : nil
        rescue
          @lock_digest = nil
        end

        private

        def extract_path(uri_or_path)
          return nil if uri_or_path.nil?
          return uri_or_path.path if uri_or_path.is_a?(URI::Generic)

          uri_or_path.to_s
        rescue
          nil
        end

        def build_specs(specs)
          locked = specs || locked_specs
          candidates = Array(locked).filter_map do |spec|
            path = spec_path(spec)
            next unless path

            Spec.new(spec.name, spec.version.to_s, path)
          end

          candidates.concat(default_specs)
          candidates.uniq!(&:path)
          # Longest path first so nested gem directories cannot shadow a more specific match.
          candidates.sort_by! { |spec| -spec.path.length }
          candidates
        end

        def locked_specs
          return [] unless defined?(Bundler) && Bundler.respond_to?(:locked_gems)

          Bundler.locked_gems&.specs
        rescue
          []
        end

        def default_specs
          return [] unless defined?(Gem)

          Gem.loaded_specs.values.filter_map do |spec|
            path = spec_path(spec)
            path ? Spec.new(spec.name, spec.version.to_s, path) : nil
          end
        rescue
          []
        end

        def spec_path(spec)
          path = spec.respond_to?(:full_gem_path) ? spec.full_gem_path : nil
          path ||= spec.gem_dir if spec.respond_to?(:gem_dir)
          return nil unless path

          path.to_s.delete_suffix("/")
        rescue
          nil
        end

        def default_lockfile
          File.expand_path("Gemfile.lock", Dir.pwd)
        rescue
          nil
        end
      end
    end
  end
end
