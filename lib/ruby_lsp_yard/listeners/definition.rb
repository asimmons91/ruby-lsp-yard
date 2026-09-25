# frozen_string_literal: true

require "prism"

require_relative "responses"

module RubyLsp
  module Yard
    module Listeners
      # Jumps to the definitions of `recv.m` when the receiver's type was inferred from YARD (FR-M2-19). When the
      # add-on knows the receiver, its precise targets replace Ruby LSP's fallback list of every method with that name;
      # when it does not, the host response is left untouched (D7). Never raises out of the request (NFR-R2).
      class Definition
        include RubyLsp::Requests::Support::Common
        include Responses

        def initialize(response_builder, node_context, dispatcher, adapter:, inference:, macros: nil, log: nil)
          @response_builder = response_builder
          @node_context = node_context
          @adapter = adapter
          @inference = inference
          @macros = macros
          @log = log

          dispatcher.register(self, :on_call_node_enter)
        end

        def on_call_node_enter(node)
          return unless node.receiver

          message = node.message.to_s
          return if message.empty?

          resolution = @inference.resolution_for(@node_context)
          return unless resolution&.yard?
          return if resolution.empty? || resolution.duck_methods.any?

          links = resolution.members.flat_map do |member|
            found = @adapter.method_definitions(member.owner, message, singleton: member.singleton).filter_map do |definition|
              link_for(definition)
            end
            # FR-M7-01: macro-generated methods have no index entry, so fall back to their call-site location
            # (including ancestors, which inherit generated methods).
            if found.empty? && @macros
              macro_links(member, message)
            else
              found
            end
          end
          links.uniq! { |link| link_key(link) }
          return if links.empty?

          prune_host_items
          links.each { |link| @response_builder << link }
        rescue => e
          @log&.error("Definition listener failed: #{e.class}: #{e.message}")
        end

        private

        def link_for(definition)
          location = definition.full_location || definition.location
          selection = definition.location || location
          return nil unless definition.uri && location && selection

          Interface::LocationLink.new(
            target_uri: definition.uri.to_s,
            target_range: range_from_location(location),
            target_selection_range: range_from_location(selection)
          )
        end

        def link_for_signature(signature)
          return nil unless signature.uri && signature.location

          Interface::LocationLink.new(
            target_uri: signature.uri.to_s,
            target_range: range_from_location(signature.location),
            target_selection_range: range_from_location(signature.location)
          )
        end

        def macro_links(member, message)
          @adapter.ancestors(member.owner).filter_map do |ancestor|
            signature = @macros.lookup(ancestor, message, singleton: member.singleton)
            signature ? link_for_signature(signature) : nil
          end
        end

        def link_key(link)
          [link.target_uri, link.target_selection_range.start.line, link.target_selection_range.start.character]
        end

        # The host emits every method with the requested name as a fallback. Its items all belong to this request, so
        # they can be replaced by the precise targets.
        def prune_host_items
          return unless prune_supported?

          prune_response_items do |item|
            item.is_a?(Interface::LocationLink) || item.is_a?(Interface::Location)
          end
        end
      end
    end
  end
end
