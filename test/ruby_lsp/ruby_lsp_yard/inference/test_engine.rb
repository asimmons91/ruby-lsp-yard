# frozen_string_literal: true

require "test_helper"
require "ruby_lsp_yard/inference"
require "ruby_lsp_yard/signature_store"

module RubyLsp
  module Yard
    module Inference
      class TestEngine < Minitest::Test
        include IndexHelpers
        include InferenceHelpers

        DOCUMENTED = "FixtureProject::Documented"
        INFERABLE = "FixtureProject::Inferable"

        class << self
          # Core signatures are needed so `String`, `Array` and friends resolve, matching a real Ruby LSP session.
          def core_index
            @core_index ||= Object.new.extend(IndexHelpers).build_core_index
          end
        end

        def setup
          @adapter = Indexer::RubyIndexerAdapter.new(index)
          @store = SignatureStore.new(@adapter)
          @engine = Engine.new(adapter: @adapter, store: @store)
        end

        def index
          self.class.core_index
        end

        def test_infers_literal_types
          assert_equal Types::Instance.new("String"), type_of('"text"')
          assert_equal Types::Instance.new("String"), type_of("\"inter\#{1}polated\"")
          assert_equal Types::Instance.new("String"), type_of("<<~TEXT\n  heredoc\nTEXT")
          assert_equal Types::Instance.new("Symbol"), type_of(":symbol")
          assert_equal Types::Instance.new("Integer"), type_of("42")
          assert_equal Types::Instance.new("Float"), type_of("4.2")
          assert_equal Types::Instance.new("Rational"), type_of("1r")
          assert_equal Types::Instance.new("Complex"), type_of("1i")
          assert_equal Types::Instance.new("Range"), type_of("(1..3)")
          assert_equal Types::Instance.new("Regexp"), type_of("/text/")
          assert_equal Types::NIL_TYPE, type_of("nil")
          assert_equal Types::BOOLEAN, type_of("true")
          assert_equal Types::BOOLEAN, type_of("false")
        end

        def test_infers_array_and_hash_with_element_types
          array = type_of('[1, "two"]')
          assert_equal "Array", array.name
          assert_equal [Types.union([Types::Instance.new("Integer"), Types::Instance.new("String")])], array.type_args

          assert_equal Types::Instance.new("Hash"), type_of("{a: 1}")
        end

        def test_infers_singletons_and_instances
          assert_equal Types::Singleton.new(DOCUMENTED), type_of("FixtureProject::Documented")
          assert_equal Types::Instance.new(DOCUMENTED), type_of("FixtureProject::Documented.new")
          assert_equal Types::Instance.new(DOCUMENTED), type_of("Documented.new", nesting: ["FixtureProject"])
        end

        def test_respects_a_documented_new_return_type
          assert_equal(
            Types::Instance.new("String"),
            type_of("FixtureProject::TypedConstructor.new")
          )
        end

        def test_infers_self_in_instance_and_singleton_methods
          instance_source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  self
                end
              end
            end
          RUBY
          singleton_source = <<~RUBY
            module FixtureProject
              class Documented
                def self.use
                  self
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new(DOCUMENTED), type_at(instance_source, "self", node_types: [Prism::SelfNode])
          assert_equal(
            Types::Singleton.new(DOCUMENTED),
            type_at(singleton_source, "self", node_types: [Prism::SelfNode], occurrence: 1)
          )
        end

        def test_infers_parameters_from_param_tags
          source = <<~RUBY
            module FixtureProject
              class Documented
                def required_keyword(key:)
                  key.to_s
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new("Symbol"), receiver_type(source, "key.to_s")
        end

        def test_infers_locals_assigned_before_a_block
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  doc = FixtureProject::Documented.new
                  [1].each do |value|
                    doc.fetch(:key)
                  end
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new(DOCUMENTED), receiver_type(source, "doc.fetch")
        end

        def test_infers_locals_from_the_enclosing_method_inside_a_lambda
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  doc = FixtureProject::Documented.new
                  -> { doc.fetch(:key) }
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new(DOCUMENTED), receiver_type(source, "doc.fetch")
        end

        def test_repeated_calls_in_a_chain_are_not_cut_off
          assert_equal(
            Types::Instance.new(DOCUMENTED),
            type_of("FixtureProject::Documented.new.chain.chain")
          )
        end

        def test_documented_self_new_with_self_return_is_an_instance
          assert_equal(
            Types::Instance.new("FixtureProject::SelfConstructor"),
            type_of("FixtureProject::SelfConstructor.new")
          )
        end

        def test_union_with_a_duck_still_contributes_class_member_returns
          assert_equal(
            Types::Instance.new("Integer"),
            type_of("FixtureProject::Inferable.new.mixed.count")
          )
        end

        def test_infers_locals_from_assignments_before_the_cursor
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  doc = FixtureProject::Documented.new
                  doc.fetch(:key)
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new(DOCUMENTED), receiver_type(source, "doc.fetch")
        end

        def test_unions_local_assignments_in_order
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  value = "text"
                  value = 1
                  value.to_s
                end
              end
            end
          RUBY

          type = receiver_type(source, "value.to_s")

          assert_instance_of Types::Union, type
          assert_equal(
            [Types::Instance.new("String"), Types::Instance.new("Integer")],
            type.types
          )
        end

        def test_ignores_assignments_after_the_cursor
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  value.fetch(:key)
                  value = 1
                end
              end
            end
          RUBY

          assert_equal Types::UNKNOWN, receiver_type(source, "value.fetch")
        end

        def test_infers_instance_variables_from_attribute_docs
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  @title.to_s
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new("String"), receiver_type(source, "@title.to_s")
        end

        def test_infers_instance_variables_from_class_assignments
          source = <<~RUBY
            module FixtureProject
              class Inferable
                def use
                  @count.to_s
                end
              end
            end
          RUBY

          assert_equal Types::Instance.new("Integer"), receiver_type(source, "@count.to_s")
        end

        def test_infers_return_types_of_call_chains
          assert_equal(
            Types::Instance.new(DOCUMENTED),
            type_of("FixtureProject::Documented.new.chain")
          )
          assert_equal(
            Types::Instance.new("Array", [Types::Instance.new("String")]),
            type_of("FixtureProject::Inferable.new.names")
          )
        end

        def test_infers_block_parameters_from_yieldparam_tags
          source = <<~RUBY
            FixtureProject::Documented.new.each_value do |value|
              value.to_s
            end
          RUBY

          assert_equal Types::Instance.new("String"), receiver_type(source, "value.to_s")
        end

        def test_resolves_unions_for_completion
          resolution = resolution_of("FixtureProject::Inferable.new.pick_any.")

          assert_equal [DOCUMENTED, "FixtureProject::Dog"], resolution.members.map(&:owner)
          refute resolution.members.any?(&:singleton)
        end

        def test_resolves_duck_types
          resolution = resolution_of("FixtureProject::Inferable.new.duckish.")

          assert_empty resolution.members
          assert_equal ["to_s", "inspect"], resolution.duck_methods
        end

        def test_drops_nil_from_union_receivers
          resolution = resolution_of("FixtureProject::Inferable.new.maybe_self.")

          assert_equal [INFERABLE], resolution.members.map(&:owner)
        end

        def test_owner_for_keeps_the_m1_entry_point
          source = "FixtureProject::Dog.species\n"
          context = context_for(source, "FixtureProject::Dog.species", node_types: [Prism::CallNode])

          assert_equal ["FixtureProject::Dog", true], @engine.owner_for(context)
        end

        def test_falls_back_to_the_host_inferrer
          type = Struct.new(:name)
          host_inferrer = Object.new
          host_inferrer.define_singleton_method(:infer_receiver_type) { |_context| type.new(DOCUMENTED) }

          engine = Engine.new(adapter: @adapter, store: @store, host: host_inferrer)
          context = context_for("mystery.fetch(:key)\n", "mystery.fetch", node_types: [Prism::CallNode])
          resolution = engine.resolution_for(context)

          refute_nil resolution
          assert_equal :host, resolution.source
          assert_equal [DOCUMENTED], resolution.members.map(&:owner)
        end

        def test_returns_nil_for_unknown_receivers
          source = <<~RUBY
            module FixtureProject
              class Documented
                def use
                  mystery.fetch(:key)
                end
              end
            end
          RUBY

          assert_nil @engine.resolution_for(context_for(source, "mystery.fetch", node_types: [Prism::CallNode]))
        end

        def test_budget_cuts_off_deep_chains
          expression = "FixtureProject::Documented.new" + (".chain" * 20)
          source = "def work\n  value = #{expression}\nend\n"
          document = document_for(source)
          write = find_node(document.ast, Prism::LocalVariableWriteNode)
          context = context_for(source, "value =")

          assert_equal Types::UNKNOWN, @engine.type_for(write.value, context)
        end

        def test_logs_inference_when_debug_is_enabled
          messages = []
          log = Object.new
          log.define_singleton_method(:debug) { |message| messages << message }
          engine = Engine.new(adapter: @adapter, store: @store, log: log, debug: true)
          context = context_for("FixtureProject::Dog.species\n", "FixtureProject::Dog.species", node_types: [Prism::CallNode])

          engine.resolution_for(context)

          assert(
            messages.any? { |message| message.include?("Inference: FixtureProject::Dog.species -> Class<FixtureProject::Dog>") },
            messages.inspect
          )
        end

        def test_never_raises_from_malformed_input
          assert_equal Types::UNKNOWN, @engine.type_for(nil, nil)
        end

        private

        def type_of(expression, source: nil, nesting: [])
          source ||= "def work\n  value = #{expression}\nend\n"
          document = document_for(source)
          write = find_node(document.ast, Prism::LocalVariableWriteNode)
          context = context_for(source, "value =")
          context.instance_variable_set(:@nesting, nesting) if nesting.any?

          @engine.type_for(write.value, context)
        end

        def type_at(source, marker, node_types: [], occurrence: 0)
          context = context_for(source, marker, node_types: node_types, occurrence: occurrence)

          @engine.type_for(context.node, context)
        end

        # The type of the receiver of the call whose source contains `marker`.
        def receiver_type(source, marker)
          context = context_for(source, marker, node_types: [Prism::CallNode])

          @engine.type_for(context.node.receiver, context)
        end

        def resolution_of(source)
          context = context_for(source, source.rstrip, node_types: [Prism::CallNode])

          @engine.resolution_for(context)
        end
      end
    end
  end
end
