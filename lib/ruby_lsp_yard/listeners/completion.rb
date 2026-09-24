# frozen_string_literal: true

require "prism"

require_relative "../host_context"
require_relative "../types"
require_relative "responses"

module RubyLsp
  module Yard
    module Listeners
      # Adds methods of the receiver's inferred type to completion (FR-M2-14..18). Ruby LSP dispatches only the target
      # call node, so inference starts from that node's receiver. Items enriched with YARD types replace the host's
      # untyped items with the same label; methods without YARD types are left to the host listener so the two never
      # duplicate. Never raises out of the request (NFR-R2).
      class Completion
        include RubyLsp::Requests::Support::Common
        include Responses

        # Caps the per-request enrichment work. Rubydex exposes the full ancestor chain for core classes (String has
        # ~270 candidates, warm enrichment measured at ~7 ms), so the cap must be high enough to cover them or the
        # enriched item set would depend on backend member ordering (FR-M6-04).
        ENRICHMENT_LIMIT = 300

        def initialize(response_builder, node_context, dispatcher, adapter:, store:, inference:, log: nil)
          @response_builder = response_builder
          @node_context = node_context
          @adapter = adapter
          @store = store
          @inference = inference
          @log = log
          @ancestor_cache = {}

          dispatcher.register(self, :on_call_node_enter)
        end

        def on_call_node_enter(node)
          receiver = node.receiver
          return unless receiver

          prefix = method_prefix(node)
          range = completion_range(node, prefix)
          return unless range

          resolution = @inference.resolution_for(@node_context)
          return unless resolution
          return if resolution.empty?

          items = if resolution.members.empty?
            []
          else
            member_items(resolution, prefix, range, internal: receiver.is_a?(Prism::SelfNode))
          end
          items += duck_items(resolution, range).reject do |item|
            items.any? { |existing| existing.label == item.label }
          end
          return if items.empty?

          replace_existing(items, resolution)
          items.each { |item| @response_builder << item }
        rescue => e
          @log&.error("Completion listener failed: #{e.class}: #{e.message}")
        end

        private

        # FR-M2-17: replace host items we can enrich, otherwise drop our items whose label the host already emitted.
        def replace_existing(items, resolution)
          labels = items.map(&:label)
          if resolution.yard? && prune_supported? &&
              prune_response_items do |item|
                item.is_a?(Interface::CompletionItem) && labels.include?(item.label)
              end
            return
          end

          existing = response_items.filter_map { |item| item.label if item.is_a?(Interface::CompletionItem) }
          items.reject! { |item| existing.include?(item.label) }
        end

        def member_items(resolution, prefix, range, internal:)
          member_count = resolution.members.size
          entries = collect_entries(resolution, prefix, internal)

          items = []
          entries.each_value do |entry|
            break if items.size >= ENRICHMENT_LIMIT

            signature = signature_for(entry)
            next unless signature&.renderable?

            items << completion_item(entry, signature, range, partial: entry[:labels].size < member_count)
          end
          items
        end

        def collect_entries(resolution, prefix, internal)
          entries = {}

          resolution.members.each_with_index do |member, member_index|
            candidates = @adapter.completion_candidates(member.owner, prefix: prefix, singleton: member.singleton)

            candidates.each do |definition|
              name = definition.name
              next if name.empty? || name.end_with?("=")
              next unless [:method, :attribute, :method_alias].include?(definition.kind)
              next unless visible?(definition.visibility, internal, member)

              entry = entries[name] ||= {definition: definition, member: member, member_index: member_index, labels: []}
              entry[:labels] << member.label unless entry[:labels].include?(member.label)
            end
          end

          entries
        end

        # FR-M3-02: the receiver's generic arguments bind RBS type variables in the label details.
        def signature_for(entry)
          signature = @store.lookup(entry[:member].owner, entry[:definition].name, singleton: entry[:member].singleton)
          return nil unless signature

          signature.with_type_bindings(type_bindings(entry[:member], signature))
        end

        def type_bindings(member, signature)
          params = Array(signature.type_params)
          args = Array(member.type_args)
          return {} if params.empty? || args.empty?

          params.zip(args).to_h
        end

        # FR-M2-14: label details carry the typed parameter list and the return type, with the eager summary as
        # documentation because Ruby LSP 0.26 has no completion resolve hook for add-ons. FR-M2-09 labels methods
        # that exist on only part of a union with the member types that provide them.
        def completion_item(entry, signature, range, partial: false)
          detail = signature.parameter_list
          detail = "#{detail} (#{entry[:labels].join(", ")})" if partial
          description = resolved_return_type(entry, signature)
          summary = signature.summary.to_s.strip

          options = {
            label: entry[:definition].name,
            filter_text: entry[:definition].name,
            kind: RubyLsp::Constant::CompletionItemKind::METHOD,
            detail: detail,
            label_details: Interface::CompletionItemLabelDetails.new(detail: detail, description: description),
            text_edit: Interface::TextEdit.new(range: range, new_text: entry[:definition].name),
            sort_text: format("%04d%s", rank_for(entry), entry[:definition].name)
          }
          options[:documentation] = summary unless summary.empty?

          Interface::CompletionItem.new(**options)
        end

        # `@return [self]` is shown as the resolved member type in completion labels.
        def resolved_return_type(entry, signature)
          return nil if Types.unknown?(signature.return_types)

          member = entry[:member]
          replacement = member.singleton ? Types::Singleton.new(member.owner) : Types::Instance.new(member.owner)
          Types::Formatter.format(Types.substitute_self(signature.return_types, replacement))
        end

        # FR-M2-16: the receiver's own class first, then ancestors in order, then union members in order.
        def rank_for(entry)
          ancestors = ancestors_for(entry[:member].owner)
          index = ancestors.index(entry[:definition].owner) || ancestors.size
          (entry[:member_index] * 1000) + index
        end

        # FR-M2-10: a duck type offers exactly the listed methods.
        def duck_items(resolution, range)
          resolution.duck_methods.map do |name|
            Interface::CompletionItem.new(
              label: name,
              filter_text: name,
              kind: RubyLsp::Constant::CompletionItemKind::METHOD,
              text_edit: Interface::TextEdit.new(range: range, new_text: name)
            )
          end
        end

        # FR-M2-15: private and protected methods are only offered for internal receivers, protected ones only within
        # the same class family.
        def visible?(visibility, internal, member)
          case visibility
          when :private
            internal
          when :protected
            internal || same_class_family?(member)
          else
            true
          end
        end

        def same_class_family?(member)
          enclosing = enclosing_class
          return false if enclosing.nil?

          member.owner == enclosing ||
            ancestors_for(member.owner).include?(enclosing) ||
            ancestors_for(enclosing).include?(member.owner)
        end

        def enclosing_class
          owner = HostContext.owner(@node_context)
          owner.empty? ? nil : owner
        end

        def ancestors_for(owner)
          @ancestor_cache[owner] ||= @adapter.ancestors(owner)
        end

        # The typed prefix. When completion is triggered by a dot, Prism matches the call's message to whatever token
        # follows in the source (Ruby LSP checks the trigger character for the same reason; add-on listeners do not
        # receive it). A message that does not start where the call operator ends is not what the user is typing.
        def method_prefix(node)
          message = node.message.to_s
          return nil if message.empty?

          operator = node.call_operator_loc
          location = node.message_loc
          return nil if operator && location && location.start_offset != operator.end_offset

          message
        end

        # In the trigger-dot case the message location points at the next token, so the edit must be an insertion
        # right after the operator instead.
        def completion_range(node, prefix)
          operator = node.call_operator_loc
          if prefix.nil? && operator
            position = Interface::Position.new(line: operator.end_line - 1, character: operator.end_column)
            return Interface::Range.new(start: position, end: position)
          end

          location = node.message_loc
          location ? range_from_location(location) : nil
        end
      end
    end
  end
end
