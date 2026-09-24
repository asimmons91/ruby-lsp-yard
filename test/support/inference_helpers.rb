# frozen_string_literal: true

# Builds `NodeContext` objects from in-memory sources so inference can be tested without starting the server. The
# inference engine reaches the enclosing scope through `NodeContext`'s private nesting nodes, exactly like in a real
# request.
module InferenceHelpers
  def global_state
    @global_state ||= RubyLsp::GlobalState.new
  end

  def document_for(source, uri: URI("file:///inference_test.rb"))
    RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: global_state)
  end

  # Locates the innermost node of the given types that covers `marker`. `occurrence` picks between repeated markers.
  def context_for(source, marker, node_types: [], occurrence: 0)
    document = document_for(source)
    offset = -1
    (occurrence + 1).times { offset = source.index(marker, offset + 1) }
    raise ArgumentError, "marker #{marker.inspect} not found in source" unless offset

    RubyLsp::RubyDocument.locate(
      document.ast,
      offset + marker.length - 1,
      node_types: node_types,
      code_units_cache: document.code_units_cache
    )
  end

  def find_node(root, klass)
    stack = [root]
    until stack.empty?
      current = stack.pop
      return current if current.is_a?(klass)

      stack.concat(current.compact_child_nodes)
    end
    nil
  end
end
