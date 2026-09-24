# frozen_string_literal: true

require "prism"

require_relative "../types"
require_relative "budget"
require_relative "resolution"
require_relative "scope_index"

module RubyLsp
  module Yard
    module Inference
      # Infers the type of expressions from YARD tags and code (FR-M2-01..13). It replaces the M1 wrapper around Ruby
      # LSP's `TypeInferrer`: the host inferrer stays as the last-resort fallback for whole receivers, while YARD
      # types, parameters, local and instance variable assignments and call chains are resolved here (NFR-P3, NFR-R3).
      # Never raises out of a request: failures degrade to Unknown or to the host fallback (NFR-R1, NFR-R2).
      class Engine
        HOST_DEFAULT_OWNERS = ["Class", "Object"].freeze

        def initialize(adapter:, store:, host: nil, log: nil, budget_ms: Budget::DEFAULT_TIMEOUT_MS, debug: false)
          @adapter = adapter
          @store = store
          @host = host
          @log = log
          @budget_ms = budget_ms
          @debug = debug
        end

        # The `[owner, singleton]` pair of the receiver of the call in `node_context`, or nil when it cannot be
        # inferred. Kept as the M1-compatible entry point for hover.
        def owner_for(node_context)
          member = resolution_for(node_context)&.primary
          member ? [member.owner, member.singleton] : nil
        rescue => e
          log_failure("owner_for", e)
          nil
        end

        # The signature for the call in `node_context`, with the receiver's generic arguments substituted so hover
        # shows `Array<Integer>#first → Integer` instead of `→ E` (FR-M3-02). Nil when it cannot be resolved.
        def signature_for(node_context)
          node = node_context&.node
          return nil unless node.is_a?(Prism::CallNode)

          message = node.message.to_s
          return nil if message.empty?

          member = resolution_for(node_context)&.primary
          return nil unless member

          signature = @store.lookup(member.owner, message, singleton: member.singleton)
          return nil unless signature

          signature.with_type_bindings(type_bindings(signature, member))
        rescue => e
          log_failure("signature_for", e)
          nil
        end

        # Resolves the receiver of the call in `node_context` into indexable owners or duck methods (FR-M2-09/10).
        def resolution_for(node_context)
          node = node_context&.node
          return nil unless node.is_a?(Prism::CallNode)

          budget = budget_for
          scope = ScopeIndex.new(node_context, log: @log)
          receiver = unwrap(node.receiver)
          type = receiver ? infer(receiver, node_context, budget, scope) : self_type(node_context)
          resolution = resolution_from(type, node_context)
          resolution = host_resolution(node_context) if resolution.nil? || resolution.empty?
          log_inference(node, resolution) if @debug
          resolution
        rescue Budget::Exceeded
          nil
        rescue => e
          log_failure("resolution_for", e)
          nil
        end

        def type_for(node, node_context, budget: nil)
          infer(node, node_context, budget || budget_for, ScopeIndex.new(node_context, log: @log))
        rescue Budget::Exceeded
          Types::UNKNOWN
        rescue => e
          log_failure("type_for", e)
          Types::UNKNOWN
        end

        private

        def budget_for
          Budget.new(timeout_ms: @budget_ms)
        end

        # `bindings` carries block parameter types while inferring a call's block body from the call node
        # (FR-M3-03); it is nil for ordinary inference.
        def infer(node, ctx, budget, scope, depth = 0, bindings = nil)
          budget.check!(depth)
          node = unwrap(node)
          return Types::UNKNOWN unless node

          case node
          when Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode
            instance("String")
          when Prism::SymbolNode, Prism::InterpolatedSymbolNode
            instance("Symbol")
          when Prism::IntegerNode
            instance("Integer")
          when Prism::FloatNode
            instance("Float")
          when Prism::RationalNode
            instance("Rational")
          when Prism::ImaginaryNode
            instance("Complex")
          when Prism::ArrayNode
            instance("Array", array_type_args(node, ctx, budget, scope, depth, bindings))
          when Prism::HashNode, Prism::KeywordHashNode
            hash_type(node, ctx, budget, scope, depth, bindings)
          when Prism::RangeNode
            instance("Range")
          when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
            instance("Regexp")
          when Prism::NilNode
            Types::NIL_TYPE
          when Prism::TrueNode, Prism::FalseNode
            Types::BOOLEAN
          when Prism::LambdaNode
            instance("Proc")
          when Prism::SelfNode
            self_type(ctx)
          when Prism::ConstantReadNode, Prism::ConstantPathNode
            constant_type(node, ctx)
          when Prism::LocalVariableReadNode
            local_type(node.name.to_s, node, ctx, budget, scope, depth, bindings)
          when Prism::InstanceVariableReadNode
            ivar_type(node.name.to_s, ctx, budget, scope, depth, bindings)
          when Prism::CallNode
            call_type(node, ctx, budget, scope, depth, bindings)
          else
            Types::UNKNOWN
          end
        end

        # --- Expressions -------------------------------------------------------------------------------------------

        def constant_type(node, ctx)
          resolved = @adapter.resolve_constant(node.slice, ctx.nesting)
          resolved ? Types::Singleton.new(resolved) : Types::UNKNOWN
        end

        def call_type(node, ctx, budget, scope, depth, bindings)
          budget.check!(depth + 1)
          receiver = unwrap(node.receiver)
          receiver_type = receiver ? infer(receiver, ctx, budget, scope, depth + 1, bindings) : self_type(ctx)

          return new_type(receiver_type, ctx) if node.message == "new" && !Types.unknown?(receiver_type)

          message = node.message.to_s
          return Types::UNKNOWN if message.empty?

          resolution = resolution_from(receiver_type, ctx)
          return Types::UNKNOWN unless resolution
          # Duck members carry no owner to look up; class members of a union still contribute return types.

          returns = resolution.members.filter_map do |member|
            location = node.location
            key = [
              member.owner,
              member.singleton,
              message,
              type_key(receiver_type),
              location.start_offset,
              location.end_offset
            ]
            next unless budget.visit(key)

            signature = @store.lookup(member.owner, message, singleton: member.singleton)
            next unless signature
            next if Types.unknown?(signature.return_types)

            type = substitute_self(signature.return_types, receiver_type)
            type = substitute_type_vars(type, type_bindings(signature, member))
            type = bind_block_return(node, ctx, budget, scope, depth, member, signature, type)
            next unless usable?(type)

            type
          end

          returns.empty? ? Types::UNKNOWN : Types.union(returns)
        end

        # FR-M2-02: `C.new` is an instance of `C` unless `new` carries its own documented return type.
        def new_type(receiver_type, ctx)
          member = resolution_from(receiver_type, ctx)&.primary
          return receiver_type unless member

          instance = Types::Instance.new(member.owner)
          signature = @store.lookup(member.owner, "new", singleton: true)
          if signature && usable?(signature.return_types) && !HOST_DEFAULT_OWNERS.include?(signature.owner)
            # `@return [self]` on `self.new` means the constructed instance, not the class object.
            substitute_self(signature.return_types, instance)
          else
            instance
          end
        end

        def local_type(name, node, ctx, budget, scope, depth, bindings)
          bound = bindings&.[](name)
          return bound if usable?(bound)

          parameter = parameter_type(name, ctx)
          return parameter if usable?(parameter)

          block_param = block_parameter_type(name, ctx, budget, scope, depth)
          return block_param if usable?(block_param)

          scope ||= ScopeIndex.new(ctx, log: @log)
          types = scope.assignment_value_nodes(name, node.location.start_offset).filter_map do |value|
            type = infer(value, ctx, budget, scope, depth + 1, bindings)
            type if usable?(type)
          end
          types.empty? ? Types::UNKNOWN : Types.union(types)
        end

        # FR-M2-04: parameters carry their `@param` type everywhere in the method body.
        def parameter_type(name, ctx)
          info = enclosing_method_info(ctx)
          return Types::UNKNOWN unless info

          owner, method, singleton = info
          signature = @store.lookup(owner, method, singleton: singleton)
          return Types::UNKNOWN unless signature

          param = signature.params.find { |candidate| normalize(candidate.name) == normalize(name) }
          return Types::UNKNOWN unless param&.typed?

          substitute_self(param.types, self_type(ctx))
        end

        # FR-M2-07: block parameters take their types from the called method's `@yieldparam` tags. FR-M3-02 adds
        # RBS block signatures, class type variable substitution and tuple destructuring (`Hash[K, V]#each`).
        def block_parameter_type(name, ctx, budget, scope, depth)
          call_node = ctx.call_node
          return Types::UNKNOWN unless call_node.is_a?(Prism::CallNode)

          scope ||= ScopeIndex.new(ctx, log: @log)
          parameters = scope.block_parameters
          return Types::UNKNOWN if parameters.empty?

          receiver_type = call_node.receiver ? infer(call_node.receiver, ctx, budget, scope, depth + 1) : self_type(ctx)
          resolution = resolution_from(receiver_type, ctx)
          return Types::UNKNOWN unless resolution

          names = parameters.map(&:first)
          resolution.members.each do |member|
            signature = @store.lookup(member.owner, call_node.message.to_s, singleton: member.singleton)
            next unless signature

            types = yield_param_types(names, signature, member)
            return types[name.to_s] if types.key?(name.to_s)
          end

          Types::UNKNOWN
        end

        # FR-M2-08: instance variables come from attribute docs or from typed assignments anywhere in the class.
        def ivar_type(name, ctx, budget, scope, depth, bindings)
          types = []
          owner = enclosing_class_owner(ctx)

          if owner
            attribute = name.delete_prefix("@")
            reader = @store.lookup(owner, attribute)
            types << reader.return_types if reader&.kind == :attribute && usable?(reader.return_types)

            writer = @store.lookup(owner, "#{attribute}=")
            writer_types = writer&.params&.first&.types
            types << writer_types if writer&.kind == :attribute && writer_types && usable?(writer_types)
          end

          scope ||= ScopeIndex.new(ctx, log: @log)
          scope.ivar_value_nodes(name).each do |value|
            type = infer(value, ctx, budget, scope, depth + 1, bindings)
            types << type if usable?(type)
          end

          types.empty? ? Types::UNKNOWN : Types.union(types)
        end

        def array_type_args(node, ctx, budget, scope, depth, bindings)
          types = node.elements.filter_map do |element|
            type = infer(element, ctx, budget, scope, depth + 1, bindings)
            type if usable?(type)
          end
          types.empty? ? [] : [Types.union(types)]
        end

        # FR-M3-02: hash literals carry their key and value unions so RBS generics can bind, e.g. `{a: 1}` is
        # `Hash[Symbol, Integer]` and `hash.each { |k, v| }` types both parameters.
        def hash_type(node, ctx, budget, scope, depth, bindings)
          keys = []
          values = []
          node.elements.each do |element|
            next unless element.is_a?(Prism::AssocNode)

            keys << element.key
            values << element.value
          end
          return instance("Hash") if keys.empty?

          key_types = keys.filter_map do |key|
            type = infer(key, ctx, budget, scope, depth + 1, bindings)
            type if usable?(type)
          end
          value_types = values.filter_map do |value|
            type = infer(value, ctx, budget, scope, depth + 1, bindings)
            type if usable?(type)
          end
          return instance("Hash") if key_types.empty? && value_types.empty?

          key_type = key_types.empty? ? Types::UNKNOWN : Types.union(key_types)
          value_type = value_types.empty? ? Types::UNKNOWN : Types.union(value_types)
          instance("Hash", [key_type, value_type])
        end

        # --- Generics and block returns (FR-M3-02, FR-M3-03) --------------------------------------------------------

        def substitute_type_vars(type, mapping)
          Types.substitute_type_vars(type, mapping)
        end

        # Class-level RBS type variables bind to the receiver's generic arguments (FR-M3-02).
        def type_bindings(signature, member)
          params = Array(signature.type_params)
          args = Array(member.type_args)
          return {} if params.empty? || args.empty?

          params.zip(args).to_h
        end

        def contains_type_var?(type, names)
          case type
          when Types::TypeVar
            names.include?(type.name)
          when Types::Union, Types::Tuple
            type.types.any? { |member| contains_type_var?(member, names) }
          when Types::Instance, Types::Singleton
            type.type_args.any? { |argument| contains_type_var?(argument, names) }
          when Types::HashOf
            contains_type_var?(type.key, names) || contains_type_var?(type.value, names)
          else
            false
          end
        end

        # FR-M3-03: binds method-level type variables, e.g. `Array#map`'s `T`, to the block's return type.
        def bind_block_return(node, ctx, budget, scope, depth, member, signature, type)
          type_params = Array(signature.method_type_params)
          return type if type_params.empty? || node.block.nil?
          return type unless contains_type_var?(type, type_params)

          block_return =
            case node.block
            when Prism::BlockArgumentNode
              block_argument_return(node.block, ctx, member)
            when Prism::BlockNode
              block_body_return(node.block, ctx, budget, scope, depth, member, signature)
            else
              Types::UNKNOWN
            end
          return type unless usable?(block_return)

          substitute_type_vars(type, type_params.zip([block_return]).to_h)
        rescue Budget::Exceeded
          type
        rescue => e
          log_failure("bind_block_return", e)
          type
        end

        def block_body_return(block, ctx, budget, scope, depth, member, signature)
          body = block.body
          return Types::UNKNOWN unless body.is_a?(Prism::StatementsNode)

          last = body.body.last
          return Types::UNKNOWN unless last

          names = ScopeIndex.block_parameters_for(block).map(&:first)
          infer(last, ctx, budget, scope, depth + 1, yield_param_types(names, signature, member))
        end

        # `map(&:strip)`: the symbol-to-proc form calls the method on each element type.
        def block_argument_return(block, ctx, member)
          symbol = block.expression
          return Types::UNKNOWN unless symbol.is_a?(Prism::SymbolNode)

          element_type = Array(member.type_args).first
          return Types::UNKNOWN unless element_type

          method_return(element_type, symbol.unescaped, ctx)
        end

        def method_return(receiver_type, message, ctx)
          resolution = resolution_from(receiver_type, ctx)
          return Types::UNKNOWN unless resolution

          returns = resolution.members.filter_map do |member|
            signature = @store.lookup(member.owner, message, singleton: member.singleton)
            next unless signature && usable?(signature.return_types)

            type = substitute_self(signature.return_types, receiver_type)
            substitute_type_vars(type, type_bindings(signature, member))
          end
          returns.empty? ? Types::UNKNOWN : Types.union(returns)
        rescue => e
          log_failure("method_return", e)
          Types::UNKNOWN
        end

        # Maps block parameter names to yield types, substituting class type variables and destructuring a single
        # tuple yield into multiple block parameters (`Hash[K, V]#each`).
        def yield_param_types(names, signature, member)
          params = signature.yield_params
          return {} if params.empty? || names.empty?

          substituted = params.map { |param| substitute_type_vars(param.types, type_bindings(signature, member)) }
          types = {}
          matched = {}

          names.each do |name|
            index = params.index { |param| normalize(param.name) == normalize(name) }
            next unless index

            types[name] = substituted[index]
            matched[index] = true
          end

          unmatched_names = names.reject { |name| types.key?(name) }
          unmatched_params = (0...params.size).reject { |index| matched[index] }

          if unmatched_names.any? && unmatched_names.size == unmatched_params.size
            unmatched_names.each_with_index { |name, i| types[name] = substituted[unmatched_params[i]] }
          elsif params.size == 1 && unmatched_names.size > 1
            tuple = substituted.first
            if tuple.is_a?(Types::Tuple) && tuple.types.size == names.size
              names.each_with_index { |name, i| types[name] ||= tuple.types[i] }
            end
          end

          types
        end

        # --- Type resolution into owners ---------------------------------------------------------------------------

        def resolution_from(type, ctx)
          case type
          when Types::Unknown
            nil
          when Types::Instance
            member_resolution(type.name, false, type_args: type.type_args)
          when Types::Singleton
            member_resolution(type.name, true, type_args: type.type_args)
          when Types::Ref
            resolved = @adapter.resolve_constant(type.name, ctx.nesting)
            resolved ? member_resolution(resolved, false, label: type.name) : nil
          when Types::Union
            union_resolution(type, ctx)
          when Types::Tuple
            member_resolution("Array", false)
          when Types::HashOf
            member_resolution("Hash", false)
          when Types::Literal
            resolution_from(Types.literal_class(type), ctx)
          when Types::Duck
            Resolution.new(duck_methods: type.methods)
          when Types::Special
            special_resolution(type, ctx)
          end
        end

        def member_resolution(owner, singleton, label: nil, type_args: [])
          Resolution.new(members: [
            Resolution::Member.new(owner, singleton, label || member_label(owner, singleton), type_args)
          ])
        end

        def union_resolution(type, ctx)
          members = []
          ducks = []
          type.types.each do |member_type|
            resolution = resolution_from(member_type, ctx)
            next unless resolution

            members.concat(resolution.members)
            ducks.concat(resolution.duck_methods)
          end
          Resolution.new(members: members.uniq(&:owner), duck_methods: ducks.uniq)
        end

        def special_resolution(type, ctx)
          case type.name
          when :boolean
            Resolution.new(members: [
              Resolution::Member.new("TrueClass", false, "TrueClass"),
              Resolution::Member.new("FalseClass", false, "FalseClass")
            ])
          when :self
            resolution_from(self_type(ctx), ctx)
          end
        end

        def host_resolution(node_context)
          return nil unless @host

          type = @host.infer_receiver_type(node_context)
          return nil unless type&.name

          name = type.name
          marker = name.rindex("::<Class:")
          if marker && name.end_with?(">")
            owner = name[0...marker]
            Resolution.new(members: [Resolution::Member.new(owner, true, owner)], source: :host)
          else
            Resolution.new(members: [Resolution::Member.new(name, false, name)], source: :host)
          end
        rescue
          nil
        end

        # --- Context helpers ---------------------------------------------------------------------------------------

        def self_type(ctx)
          nesting = Array(ctx.nesting)
          return Types::UNKNOWN if nesting.empty?

          singleton = nesting.any? { |part| part.start_with?("<Class:") }
          owner = nesting.reject { |part| part.start_with?("<Class:") }.join("::")
          return Types::UNKNOWN if owner.empty?

          if singleton || ctx.surrounding_method.nil?
            Types::Singleton.new(owner)
          else
            Types::Instance.new(owner)
          end
        end

        def enclosing_method_info(ctx)
          method = ctx.surrounding_method
          return nil unless method

          nesting = Array(ctx.nesting)
          singleton = nesting.any? { |part| part.start_with?("<Class:") }
          owner = nesting.reject { |part| part.start_with?("<Class:") }.join("::")
          return nil if owner.empty?

          [owner, method, singleton]
        end

        def enclosing_class_owner(ctx)
          nesting = Array(ctx.nesting).reject { |part| part.start_with?("<Class:") }
          nesting.empty? ? nil : nesting.join("::")
        end

        # --- Small helpers -----------------------------------------------------------------------------------------

        def unwrap(node)
          return nil unless node

          if node.is_a?(Prism::ParenthesesNode)
            body = node.body
            if body.is_a?(Prism::StatementsNode) && body.body.length == 1
              return unwrap(body.body.first)
            end
          end

          node
        end

        def substitute_self(type, receiver_type)
          Types.substitute_self(type, receiver_type)
        end

        def usable?(type)
          !type.nil? && !Types.unknown?(type) && type != Types::UNTYPED
        end

        def instance(name, type_args = [])
          type_args.empty? ? Types::Instance.new(name) : Types::Instance.new(name, type_args)
        end

        def member_label(owner, singleton)
          singleton ? "Class<#{owner}>" : owner
        end

        def type_key(type)
          Types::Formatter.format(type)
        end

        # NFR-O2: with `debugInference`, log how a receiver was resolved.
        def log_inference(node, resolution)
          return unless resolution

          source = node.receiver ? node.receiver.slice.to_s.split("\n").first : "self"
          details = if resolution.duck_methods.any?
            "duck #{resolution.duck_methods.join(", ")}"
          else
            resolution.members.map { |member| member.singleton ? "Class<#{member.owner}>" : member.owner }.join(", ")
          end
          @log&.debug("Inference: #{source}.#{node.message} -> #{details} (#{resolution.source})")
        rescue
          nil
        end

        def normalize(name)
          name.to_s.sub(/\A[*&]+/, "").sub(/:+\z/, "")
        end

        def log_failure(operation, error)
          @log&.error("Inference #{operation} failed: #{error.class}: #{error.message}")
          nil
        end
      end
    end
  end
end
