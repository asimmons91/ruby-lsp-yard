# frozen_string_literal: true

module RubyLsp
  module Yard
    module Indexer
      # Backend-neutral view of a source location. Lines are 1-based and columns are 0-based, matching Prism and the
      # host indexer. Feature listeners convert these into LSP locations.
      Location = Struct.new(:start_line, :start_column, :end_line, :end_column)

      # Backend-neutral view of a method parameter. `kind` is one of `:required`, `:optional`, `:keyword`,
      # `:keyword_optional`, `:rest`, `:keyword_rest`, `:block` or `:forwarding`.
      Parameter = Struct.new(:name, :kind)

      # Backend-neutral view of a method, attribute, class, module or constant definition returned by the Indexer
      # Adapter. Host indexer entry objects must never leak past the adapter.
      Definition = Struct.new(
        :name,
        :owner,
        :kind,
        :visibility,
        :uri,
        :location,
        :comments,
        :parameters
      )
    end
  end
end
