# frozen_string_literal: true

require "test_helper"
require "uri"

module RubyLsp
  module Yard
    module Authoring
      class TestCommentCompletion < Minitest::Test
        include IndexHelpers

        def test_tag_completion_offers_missing_params_only
          labels = items_for(method_source, "@ret").map(&:label)

          assert_includes labels, "@param missing []"
          refute_includes labels, "@param existing []"
        end

        def test_tag_completion_decorates_splat_and_block_params
          items = items_for(splat_source, "@param")
          labels = items.map(&:label)

          assert_includes labels, "@param *rest []"
          assert_includes labels, "@param **options []"
          assert_includes labels, "@param &block []"
        end

        def test_tag_completion_ranks_return_lower_when_present
          item = items_for(method_source, "@ret").find { |candidate| candidate.filter_text == "@return" }

          refute_nil item
          assert_match(/\A0002/, item.sort_text)
        end

        def test_tag_completion_suggests_yield_tags_for_yielding_methods
          assert_includes items_for(method_source, "@ret").map(&:filter_text), "@yield"
          refute_includes items_for(plain_method_source, "@ret").map(&:filter_text), "@yield"
        end

        def test_tag_completion_prefills_the_raised_class
          item = items_for(method_source, "@ret").find { |candidate| candidate.filter_text == "@raise" }

          refute_nil item
          assert_equal "@raise [${1:KeyError}] $0", item.text_edit.new_text
        end

        def test_snippets_replace_the_whole_typed_token
          source = <<~RUBY
            module FixtureProject
              class Documented
                # @ret
                def fetch; end
              end
            end
          RUBY
          item = items_for(source, "@ret").find { |candidate| candidate.filter_text == "@return" }

          assert_equal "@return [${1:Type}] $0", item.text_edit.new_text
          assert_equal 2, item.insert_text_format
          assert_equal 6, item.text_edit.range.start.attributes[:character]
          assert_equal 10, item.text_edit.range.end.attributes[:character]
        end

        def test_plain_text_fallback_when_snippets_are_unsupported
          item = items_for(method_source, "@ret", snippets: false).find { |candidate| candidate.filter_text == "@return" }

          assert_equal "@return [Type]", item.text_edit.new_text
          assert_nil item.attributes[:insertTextFormat]
        end

        def test_directive_completion
          items = items_for("# @!\ndef foo; end\n", "@!")

          assert_equal(
            ["@!method", "@!attribute", "@!parse", "@!visibility"],
            items.map(&:label)
          )
        end

        def test_param_name_completion_uses_the_documented_method
          source = <<~RUBY
            module FixtureProject
              class Documented
                # @param 
                def fetch(existing, missing); end
              end
            end
          RUBY
          labels = items_for(source, "@param ").map(&:label)

          assert_includes labels, "@param existing"
          assert_includes labels, "@param missing"
          item = items_for(source, "@param ").find { |candidate| candidate.label == "@param missing" }
          assert_equal "@param ${1:missing} [${2:Type}] $0", item.text_edit.new_text
        end

        def test_type_completion_includes_specials_and_generics
          labels = items_for(type_source, "[Doc").map(&:label)

          %w[Boolean nil true false self void undefined Object].each { |special| assert_includes labels, special }
          assert_includes labels, "Array<T>"
          assert_includes labels, "Hash{K => V}"
          assert_includes labels, "Tuple(a, b)"
        end

        def test_type_completion_resolves_constants_relative_to_the_nesting
          item = items_for(type_source, "[Doc").find { |candidate| candidate.label == "Documented" }

          refute_nil item
          assert_equal "Documented", item.filter_text
        end

        def test_generic_falls_back_to_plain_text
          item = items_for(type_source, "[Doc", snippets: false).find { |candidate| candidate.label == "Array<T>" }

          assert_equal "Array<Type>", item.text_edit.new_text
        end

        private

        def method_source
          <<~RUBY
            module FixtureProject
              class Documented
                # @param existing [String]
                # @return [Integer]
                # @ret
                def fetch(existing, missing, key:, **options, &block)
                  yield
                  raise KeyError if existing.nil?
                end
              end
            end
          RUBY
        end

        def splat_source
          <<~RUBY
            module FixtureProject
              class Documented
                # @param
                def splat(*rest, **options, &block); end
              end
            end
          RUBY
        end

        def plain_method_source
          <<~RUBY
            module FixtureProject
              class Documented
                # @ret
                def quiet(one); end
              end
            end
          RUBY
        end

        def type_source
          <<~RUBY
            module FixtureProject
              class Documented
                # @param existing [Doc
                def fetch(existing); end
              end
            end
          RUBY
        end

        def items_for(content, token, snippets: true)
          context = build_context(content, token)
          refute_nil context
          CommentCompletion.new(context, adapter: adapter, snippets: snippets).items
        end

        def build_context(content, token)
          line = content.lines.index { |candidate| candidate.include?(token) }
          refute_nil line, "token #{token.inspect} not found"
          character = content.lines[line].index(token) + token.length
          Context.build(document_for(content), {line: line, character: character}, adapter: adapter)
        end

        def document_for(content)
          RubyLsp::RubyDocument.new(
            source: content,
            version: 1,
            uri: URI("file:///fixture.rb"),
            global_state: RubyLsp::GlobalState.new
          )
        end

        def adapter
          @adapter ||= Indexer::RubyIndexerAdapter.new(build_fixture_index)
        end
      end
    end
  end
end
