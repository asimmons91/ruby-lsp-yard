# frozen_string_literal: true

require "yaml"

require_relative "../domains"
require_relative "../log"

module RubyLsp
  module Yard
    module Solargraph
      # Reads the parts of a project's `.solargraph.yml` the add-on understands (FR-M7-03): `domains` become
      # workspace-wide DSL domains and `require` entries are recorded as hints. The file is re-read when its mtime
      # changes, because Ruby LSP only watches `**/*.rb`. Never raises: a missing or malformed file yields defaults
      # (NFR-R1).
      class Config
        FILENAME = ".solargraph.yml"

        attr_reader :path

        def initialize(workspace_path: nil, log: nil)
          @log = log
          @path = workspace_path ? File.join(workspace_path.to_s, FILENAME) : nil
          @mtime = nil
          @data = nil
        end

        def present?
          !@path.nil? && File.file?(@path)
        end

        # Workspace-wide domain type expressions, e.g. `Class<Sinatra::Base>`.
        def domains
          Array(refresh["domains"]).select { |domain| domain.is_a?(String) }
        end

        # `require` hints from the configuration. The host index decides what is actually available, so these are
        # informational (documented in the README).
        def requires
          Array(refresh["require"]).select { |entry| entry.is_a?(String) }
        end

        private

        def refresh
          return {} if @path.nil?
          return @data if @data && current_mtime == @mtime

          @mtime = current_mtime
          @data = parse
        end

        def current_mtime
          File.mtime(@path)
        rescue
          nil
        end

        def parse
          return {} unless present?

          data = YAML.safe_load_file(@path, aliases: true)
          data.is_a?(Hash) ? data : {}
        rescue => e
          @log&.warn("Failed to read #{FILENAME}: #{e.class}: #{e.message}")
          {}
        end
      end
    end
  end
end
