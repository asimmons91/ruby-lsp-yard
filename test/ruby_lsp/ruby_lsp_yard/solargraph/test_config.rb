# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "ruby_lsp_yard/solargraph"

module RubyLsp
  module Yard
    module Solargraph
      class TestConfig < Minitest::Test
        def with_config(content)
          Dir.mktmpdir do |dir|
            path = File.join(dir, Config::FILENAME)
            File.write(path, content)
            yield Config.new(workspace_path: dir), path
          end
        end

        def test_missing_file_yields_defaults
          Dir.mktmpdir do |dir|
            config = Config.new(workspace_path: dir)

            refute config.present?
            assert_empty config.domains
            assert_empty config.requires
          end
        end

        def test_reads_domains_and_requires
          with_config(<<~YAML) do |config, _path|
            domains:
              - Class<Sinatra::Base>
              - Sinatra::Helpers
            require:
              - sinatra/base
          YAML
            assert_equal ["Class<Sinatra::Base>", "Sinatra::Helpers"], config.domains
            assert_equal ["sinatra/base"], config.requires
          end
        end

        def test_malformed_yaml_falls_back_to_defaults
          with_config("domains: [unclosed") do |config, _path|
            assert_empty config.domains
            assert_empty config.requires
          end

          with_config("- just\n- a list\n") do |config, _path|
            assert_empty config.domains
          end
        end

        def test_ignores_non_string_entries
          with_config(<<~YAML) do |config, _path|
            domains:
              - 42
              - Class<Foo>
          YAML
            assert_equal ["Class<Foo>"], config.domains
          end
        end

        def test_refreshes_when_the_file_changes
          with_config("domains:\n  - First\n") do |config, path|
            assert_equal ["First"], config.domains

            File.write(path, "domains:\n  - Second\n")
            future = Time.now + 10
            File.utime(future, future, path)

            assert_equal ["Second"], config.domains
          end
        end
      end
    end
  end
end
