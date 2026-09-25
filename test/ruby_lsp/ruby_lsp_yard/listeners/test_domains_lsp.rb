# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    module Listeners
      class TestDomainsLsp < Minitest::Test
        include RubyLsp::TestHelper
        include IndexHelpers
        include LspHelpers

        DOMAIN_SOURCE = <<~RUBY
          module FixtureProject
            class DomainHost
              def use
                dsl_
              end
            end
          end
        RUBY

        PLAIN_SOURCE = <<~RUBY
          module FixtureProject
            class PlainHost
              def use
                dsl_
              end
            end
          end
        RUBY

        def test_completes_instance_domain_methods_on_implicit_self
          items = complete(DOMAIN_SOURCE, "dsl_")

          greet = find_item(items, "dsl_greet")
          refute_nil greet
          assert_equal "String", label_details(greet)[:description]

          count = find_item(items, "dsl_count")
          refute_nil count
          assert_equal "Integer", label_details(count)[:description]
        end

        def test_completes_class_domain_methods_on_implicit_self
          source = <<~RUBY
            module FixtureProject
              class DomainHost
                def use
                  bu
                end
              end
            end
          RUBY

          items = complete(source, "bu\n")

          build = find_item(items, "build")
          refute_nil build
          assert_equal "String", label_details(build)[:description]
        end

        def test_domains_do_not_leak_to_other_namespaces
          items = complete(PLAIN_SOURCE, "dsl_")

          assert_nil find_item(items, "dsl_greet")
        end

        private

        def complete(source, line_token)
          items = nil
          with_server(source) do |server, uri|
            index_fixtures(server)
            items = completion_items(server, uri, source, line_token: line_token)
          end

          items
        end

        def find_item(items, label)
          items.find { |item| item.label == label }
        end
      end
    end
  end
end
