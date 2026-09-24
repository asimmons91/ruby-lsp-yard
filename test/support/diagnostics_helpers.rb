# frozen_string_literal: true

require "ruby_lsp_yard/diagnostics"
require "ruby_lsp_yard/settings"
require "ruby_lsp_yard/signature_store"
require "ruby_lsp_yard/inference"
require "ruby_lsp_yard/indexer"

# Builds documents and runs the diagnostics linter without starting the server. Including this module gives the test
# class a shared core index that mirrors a real Ruby LSP session, so type names resolve.
module DiagnosticsHelpers
  TEST_URI = URI("file:///tmp/ruby-lsp-yard-diagnostics.rb")

  module ClassMethods
    def core_index
      @core_index ||= begin
        require "rbs"
        index = RubyIndexer::Index.new
        RubyIndexer::RBSIndexer.new(index).index_ruby_core
        index
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  def global_state
    @global_state ||= RubyLsp::GlobalState.new
  end

  def core_index
    self.class.core_index
  end

  # Indexes `source` into `index` (which defaults to the shared core index) and runs the linter over it.
  def lint(source, index: core_index, rules: nil, settings: {}, uri: TEST_URI)
    index.delete(uri)
    index.index_single(uri, source)
    adapter = RubyLsp::Yard::Indexer::RubyIndexerAdapter.new(index)
    store = RubyLsp::Yard::SignatureStore.new(adapter)
    inference = RubyLsp::Yard::Inference::Engine.new(adapter: adapter, store: store, host: global_state.type_inferrer)
    linter = RubyLsp::Yard::Diagnostics::Linter.new(
      adapter: adapter,
      store: store,
      inference: inference,
      settings: RubyLsp::Yard::Settings.new(settings),
      rules: rules
    )
    linter.run_diagnostic(uri, document_for(source, uri: uri)) || []
  end

  # Runs the linter without an adapter, for rules that do not resolve constants.
  def lint_without_index(source, rules: nil, settings: {}, uri: TEST_URI)
    linter = RubyLsp::Yard::Diagnostics::Linter.new(
      settings: RubyLsp::Yard::Settings.new(settings),
      rules: rules
    )
    linter.run_diagnostic(uri, document_for(source, uri: uri)) || []
  end

  def document_for(source, uri: TEST_URI)
    RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: global_state)
  end

  def scanner_for(source, uri: TEST_URI)
    RubyLsp::Yard::Diagnostics::Scanner.new(document_for(source, uri: uri))
  end

  # The quick-fix actions for a zero-width range at `line`/`character` (FR-M5-03).
  def fix_actions(source, line:, character: 0, index: core_index, rules: nil, settings: {}, uri: TEST_URI)
    index.delete(uri)
    index.index_single(uri, source)
    adapter = RubyLsp::Yard::Indexer::RubyIndexerAdapter.new(index)
    store = RubyLsp::Yard::SignatureStore.new(adapter)
    inference = RubyLsp::Yard::Inference::Engine.new(adapter: adapter, store: store, host: global_state.type_inferrer)
    linter = RubyLsp::Yard::Diagnostics::Linter.new(
      adapter: adapter,
      store: store,
      inference: inference,
      settings: RubyLsp::Yard::Settings.new(settings),
      rules: rules
    )
    document = document_for(source, uri: uri)
    position = RubyLsp::Interface::Position.new(line: line, character: character)
    range = RubyLsp::Interface::Range.new(start: position, end: position)

    RubyLsp::Yard::Diagnostics::Fixes.new(linter: linter, adapter: adapter, store: store)
      .actions_for(document: document, uri: uri, range: range)
  end

  def codes(diagnostics)
    diagnostics.map(&:code)
  end
end
