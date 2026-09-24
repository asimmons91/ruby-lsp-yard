# frozen_string_literal: true

module RubyLsp
  module Yard
    module Authoring
      # Builds the completion items offered inside YARD comments (FR-M4-02..05). Every item replaces the token being
      # typed through `textEdit`, so the typed `@` (or type prefix) is not duplicated. Snippet placeholders are only
      # used when the client reported support; otherwise plain text is inserted (NFR-C3).
      class CommentCompletion
        SPECIAL_TYPES = %w[Boolean nil true false self void undefined Object].freeze
        GENERIC_TYPES = [
          ["Array<T>", "Array", "Array<${1:Type}> $0"],
          ["Hash{K => V}", "Hash", "Hash{${1:Key} => ${2:Value}} $0"],
          ["Tuple(a, b)", "Tuple", "Tuple(${1:Type}, ${2:Type}) $0"],
          ["Class<T>", "Class", "Class<${1:Object}> $0"]
        ].freeze
        PLAIN_TAGS = [
          "@option",
          "@deprecated",
          "@overload",
          "@api",
          "@note",
          "@see",
          "@since",
          "@example"
        ].freeze
        DIRECTIVES = [
          ["@!method", "@!method ${1:name}(${2:params}) $0"],
          ["@!attribute", "@!attribute [${1:r}] ${2:name} $0"],
          ["@!parse", "@!parse $0"],
          ["@!visibility", "@!visibility ${1:private} $0"]
        ].freeze
        CANDIDATE_LIMIT = 100

        def initialize(context, adapter: nil, snippets: false, log: nil)
          @context = context
          @adapter = adapter
          @snippets = snippets
          @log = log
        end

        def items
          case @context.kind
          when :tag then tag_items
          when :directive then directive_items
          when :type then type_items
          when :param then param_items
          else []
          end
        rescue => e
          @log&.error("Comment completion failed: #{e.class}: #{e.message}")
          []
        end

        private

        # FR-M4-02/03: tag suggestions, including one `@param` per undocumented parameter.
        def tag_items
          items = []
          @context.parameters.each do |param|
            name = decorated(param)
            next if documented?(@context.documented_params, param.name)

            items << item(
              label: "@param #{name} []",
              filter_text: "@param #{name}",
              new_text: "@param ${1:#{name}} [${2:Type}] $0",
              plain_text: "@param #{name} []",
              rank: 0
            )
          end

          items << return_item
          items.concat(yield_items) if @context.yields?
          items << raise_item
          PLAIN_TAGS.each_with_index do |label, index|
            items << item(label: label, filter_text: label, new_text: "#{label} $0", plain_text: label, rank: 10 + index)
          end
          items
        end

        def return_item
          present = @context.raw_doc.returns.any?
          item(
            label: "@return [Type]",
            filter_text: "@return",
            new_text: "@return [${1:Type}] $0",
            plain_text: "@return [Type]",
            rank: present ? 2 : 0
          )
        end

        def yield_items
          [
            item(
              label: "@yield [args]",
              filter_text: "@yield",
              new_text: "@yield [${1:args}] $0",
              plain_text: "@yield [args]",
              rank: 1
            ),
            item(
              label: "@yieldparam name [Type]",
              filter_text: "@yieldparam",
              new_text: "@yieldparam ${1:name} [${2:Type}] $0",
              plain_text: "@yieldparam name [Type]",
              rank: 1
            ),
            item(
              label: "@yieldreturn [Type]",
              filter_text: "@yieldreturn",
              new_text: "@yieldreturn [${1:Type}] $0",
              plain_text: "@yieldreturn [Type]",
              rank: 1
            )
          ]
        end

        def raise_item
          klass = @context.raise_class
          unless klass
            return item(
              label: "@raise [Error]",
              filter_text: "@raise",
              new_text: "@raise [${1:Error}] $0",
              plain_text: "@raise [Error]",
              rank: 1
            )
          end

          item(
            label: "@raise [#{klass}]",
            filter_text: "@raise",
            new_text: "@raise [${1:#{klass}}] $0",
            plain_text: "@raise [#{klass}]",
            rank: 1
          )
        end

        # FR-M4-04: directives supported in M4. `@!macro` and `@!domain` land in M7.
        def directive_items
          DIRECTIVES.each_with_index.map do |(label, text), index|
            item(label: label, filter_text: label, new_text: text, plain_text: plain_text(text), rank: index)
          end
        end

        # FR-M4-05: constants from the index resolved relative to the definition's nesting, YARD specials and
        # snippets for the common generic shapes.
        def type_items
          items = []
          prefix = @context.prefix.to_s
          SPECIAL_TYPES.each_with_index do |name, index|
            items << item(label: name, filter_text: name, new_text: name, plain_text: name, rank: index)
          end
          GENERIC_TYPES.each_with_index do |(label, filter, text), index|
            items << item(
              label: label,
              filter_text: filter,
              new_text: text,
              plain_text: plain_text(text),
              rank: 100 + index,
              kind: Constant::CompletionItemKind::SNIPPET
            )
          end
          items.concat(constant_items(prefix, start_rank: 200))
          items
        end

        def constant_items(prefix, start_rank:)
          return [] unless @adapter

          seen = {}
          entries = []
          @adapter.constant_candidates(prefix, @context.nesting).each do |definition|
            name = relative_name(definition.name)
            next if name.empty? || seen[name] || !name.start_with?(prefix)

            seen[name] = true
            entries << [name, constant_kind(definition.kind)]
            break if entries.size >= CANDIDATE_LIMIT
          end

          entries.each_with_index.map do |(name, kind), index|
            item(label: name, filter_text: name, new_text: name, plain_text: name, rank: start_rank + index, kind: kind)
          end
        end

        def constant_kind(kind)
          case kind
          when :class then Constant::CompletionItemKind::CLASS
          when :module then Constant::CompletionItemKind::MODULE
          else Constant::CompletionItemKind::CONSTANT
          end
        end

        # FR-M4-01: completing one of the parameter names of the method the comment documents.
        def param_items
          case @context.tag_name
          when "yieldparam" then param_name_items("@yieldparam")
          when "option" then []
          else param_name_items("@param")
          end
        end

        def param_name_items(tag)
          prefix = @context.prefix.to_s
          @context.parameters.filter_map do |param|
            name = decorated(param)
            next if documented?(@context.documented_params, param.name)
            next unless name.start_with?(prefix)

            item(
              label: "#{tag} #{name}",
              filter_text: "#{tag} #{name}",
              new_text: "#{tag} ${1:#{name}} [${2:Type}] $0",
              plain_text: "#{tag} #{name} []",
              rank: 0
            )
          end
        end

        def item(label:, filter_text:, new_text:, plain_text:, rank:, kind: Constant::CompletionItemKind::SNIPPET)
          text = @snippets ? new_text : plain_text
          options = {
            label: label,
            filter_text: filter_text,
            kind: kind,
            text_edit: Interface::TextEdit.new(range: @context.token_range, new_text: text),
            sort_text: format("%04d%s", rank, filter_text)
          }
          options[:insert_text_format] = Constant::InsertTextFormat::SNIPPET if @snippets
          Interface::CompletionItem.new(**options)
        end

        def documented?(documented, name)
          documented.include?(name)
        end

        def decorated(param)
          case param.kind
          when :rest then "*#{param.name}"
          when :keyword_rest then "**#{param.name}"
          when :block then "&#{param.name}"
          else param.name.to_s
          end
        end

        # The shortest name that resolves from the documented definition's nesting (FR-M4-05).
        def relative_name(full_name)
          nesting = Array(@context.nesting)
          nesting.length.downto(1) do |size|
            namespace = nesting[0...size].join("::")
            return full_name.delete_prefix("#{namespace}::") if full_name.start_with?("#{namespace}::")
          end
          full_name
        end

        # Strips snippet syntax for the plain-text fallback.
        def plain_text(text)
          text.gsub(/\$\{\d+:(\w+)\}/, "\\1").gsub(/\$\d+|\$0/, "").strip
        end
      end
    end
  end
end
