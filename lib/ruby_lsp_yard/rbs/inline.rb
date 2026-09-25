# frozen_string_literal: true

require "prism"
require "rbs"
require "rbs/inline"

require_relative "../signature"
require_relative "converter"
require_relative "function_signature"

module RubyLsp
  module Yard
    module Rbs
      # Answers signature lookups from `rbs-inline` annotations (`#:` comments and `@rbs` tags) in workspace files
      # (FR-M7-04, D5). Files are parsed lazily, only when they opt in with the `# rbs_inline: enabled` magic comment,
      # and cached per path until watched files change. Aliases and interfaces resolve against the RBS environment when
      # a loader is available. Never raises: failures degrade to nil (NFR-R1).
      class Inline
        MAGIC = "rbs_inline"

        def initialize(adapter, log: nil, loader: nil, enabled: true)
          @adapter = adapter
          @log = log
          @loader = loader
          @enabled = enabled
          @files = {}
          @converter = nil
          @mutex = Mutex.new

          if enabled
            adapter.subscribe { invalidate }
            @loader&.subscribe { invalidate }
          end
        end

        # The inline signature for `name` on `owner` declared in the file at `uri`, or nil.
        def lookup(uri, owner, name, singleton: false)
          return nil unless @enabled

          signatures_for(uri)[[owner.to_s, name.to_s, singleton]]
        end

        def invalidate
          @mutex.synchronize do
            @files.clear
            @converter = nil
          end
        end

        private

        def signatures_for(uri)
          path = path_for(uri)
          return {} unless path

          cached = @mutex.synchronize { @files.fetch(path, nil) }
          return cached if cached

          built = parse_file(path)
          @mutex.synchronize { @files[path] = built }
          built
        end

        def parse_file(path)
          source = File.read(path, encoding: Encoding::UTF_8)
          return {} unless source.include?(MAGIC)

          parsed = ::RBS::Inline::Parser.parse(Prism.parse(source), opt_in: true)
          return {} unless parsed

          uses, decls, rbs_decls = parsed
          text = ::RBS::Inline::Writer.write(uses, decls, rbs_decls)
          return {} if text.to_s.strip.empty?

          buffer = ::RBS::Buffer.new(name: path, content: text)
          _buffer, _directives, declarations = ::RBS::Parser.parse_signature(buffer)
          collect(declarations)
        rescue => e
          @log&.warn("rbs-inline parsing failed for #{path}: #{e.class}: #{e.message}")
          {}
        end

        def collect(declarations)
          signatures = {}
          declarations.each do |declaration|
            case declaration
            when ::RBS::AST::Declarations::Class, ::RBS::AST::Declarations::Module
              owner = qualify(declaration.name.to_s, "")
              type_params = declaration.type_params.map { |param| param.name.to_sym }
              walk_members(declaration.members, owner, type_params, signatures)
            end
          end
          signatures
        end

        def walk_members(members, owner, type_params, signatures)
          visibility = :public

          members.each do |member|
            case member
            when ::RBS::AST::Members::Public
              visibility = :public
            when ::RBS::AST::Members::Private
              visibility = :private
            when ::RBS::AST::Members::MethodDefinition
              signature = method_signature(owner, member, visibility, type_params)
              signatures[[owner, member.name.to_s, singleton?(member)]] = signature if signature
            when ::RBS::AST::Members::AttrReader
              add_attribute(signatures, owner, member, visibility, type_params, reader: true, writer: false)
            when ::RBS::AST::Members::AttrWriter
              add_attribute(signatures, owner, member, visibility, type_params, reader: false, writer: true)
            when ::RBS::AST::Members::AttrAccessor
              add_attribute(signatures, owner, member, visibility, type_params, reader: true, writer: true)
            when ::RBS::AST::Declarations::Class, ::RBS::AST::Declarations::Module
              nested = qualify(member.name.to_s, owner)
              nested_params = member.type_params.map { |param| param.name.to_sym }
              walk_members(member.members, nested, nested_params, signatures)
            end
          end
        end

        # Nested declarations in the parsed RBS AST carry relative names; qualify them with the enclosing owner.
        def qualify(name, owner)
          return name.delete_prefix("::") if name.start_with?("::")

          owner.to_s.empty? ? name : "#{owner}::#{name}"
        end

        def singleton?(member)
          member.kind != :instance
        end

        def method_signature(owner, member, visibility, type_params)
          primary = member.overloads.first
          return nil unless primary

          method_type = primary.method_type
          yield_params, yield_returns = FunctionSignature.yield_info(method_type, converter)

          Signature.new(
            owner: owner,
            name: member.name.to_s,
            singleton: singleton?(member),
            visibility: member.visibility || visibility,
            params: FunctionSignature.params_from_function(method_type.type, converter),
            return_types: converter.convert(method_type.type.return_type),
            overloads: overload_signatures(owner, member, type_params),
            yield_params: yield_params,
            yield_returns: yield_returns,
            type_params: type_params,
            method_type_params: FunctionSignature.method_type_params(method_type),
            documented: true,
            source: :rbs
          )
        end

        def overload_signatures(owner, member, type_params)
          member.overloads.drop(1).map do |overload|
            method_type = overload.method_type
            yield_params, yield_returns = FunctionSignature.yield_info(method_type, converter)

            Signature.new(
              owner: owner,
              name: member.name.to_s,
              singleton: singleton?(member),
              params: FunctionSignature.params_from_function(method_type.type, converter),
              return_types: converter.convert(method_type.type.return_type),
              yield_params: yield_params,
              yield_returns: yield_returns,
              type_params: type_params,
              method_type_params: FunctionSignature.method_type_params(method_type),
              documented: true,
              source: :rbs
            )
          end
        end

        def add_attribute(signatures, owner, member, visibility, type_params, reader:, writer:)
          name = member.name.to_s
          types = converter.convert(member.type)
          singleton = member.kind == :singleton
          attr_visibility = member.visibility || visibility

          if reader
            signatures[[owner, name, singleton]] = Signature.new(
              owner: owner,
              name: name,
              singleton: singleton,
              kind: :attribute,
              visibility: attr_visibility,
              return_types: types,
              type_params: type_params,
              documented: true,
              source: :rbs
            )
          end

          if writer
            signatures[[owner, "#{name}=", singleton]] = Signature.new(
              owner: owner,
              name: "#{name}=",
              singleton: singleton,
              kind: :attribute,
              visibility: attr_visibility,
              params: [Signature::Param.new(name: :value, kind: :required, types: types)],
              type_params: type_params,
              documented: true,
              source: :rbs
            )
          end
        end

        # Aliases and interfaces resolve against the loaded environment; `invalidate` drops the converter so a
        # converter built while the loader was still running does not pin `Unknown`.
        def converter
          @converter ||= Converter.new(environment: @loader&.environment, builder: @loader&.builder)
        end

        def path_for(uri)
          return nil unless uri.respond_to?(:scheme) && uri.scheme == "file"

          path = uri.respond_to?(:full_path) ? uri.full_path : URI::DEFAULT_PARSER.unescape(uri.path)
          path if path && File.file?(path)
        rescue
          nil
        end
      end
    end
  end
end
