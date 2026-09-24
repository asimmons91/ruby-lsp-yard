# frozen_string_literal: true

# Sends real LSP requests through Ruby LSP's test server and extracts the interesting part of the response, so the
# completion and definition listener tests stay close to what an editor would see.
module LspHelpers
  def index_fixtures(server)
    if IndexHelpers.rubydex?
      graph = server.global_state.graph
      graph.index_all(IndexHelpers::FIXTURE_FILES.map { |file| fixture_path(file) })
      graph.resolve
    else
      IndexHelpers::FIXTURE_FILES.each { |file| server.global_state.index.index_file(fixture_uri(file)) }
    end
  end

  # Adds the RBS-derived core entries to the server's index, like a real Ruby LSP session does during `index_all`.
  def index_core(server)
    if IndexHelpers.rubydex?
      graph = server.global_state.graph
      graph.index_all(IndexHelpers.rbs_core_paths)
      graph.resolve
    else
      require "rbs"
      RubyIndexer::RBSIndexer.new(server.global_state.index).index_ruby_core
    end
  end

  # The add-on loads its RBS environment in the background (NFR-P1); tests that assert core types wait for it.
  def wait_for_rbs(server)
    addon = RubyLsp::Addon.addons.find { |candidate| candidate.name == "Ruby LSP YARD" }
    loader = addon&.rbs_loader
    return unless loader

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15
    sleep(0.01) until loader.ready? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  # Completion position is the end of `position_token`, or the end of the line when not given. This matches an
  # editor that has just typed the last character of the line.
  def completion_items(server, uri, source, line_token:, position_token: nil, trigger: ".")
    line = source.lines.index { |candidate| candidate.include?(line_token) }
    character = if position_token
      source.lines[line].index(position_token) + position_token.length
    else
      source.lines[line].rstrip.length
    end

    server.process_message({
      id: 1,
      method: "textDocument/completion",
      params: {
        textDocument: {uri: uri},
        position: {line: line, character: character},
        context: {triggerCharacter: trigger}
      }
    })

    pop_result(server).response.select { |item| item.is_a?(RubyLsp::Interface::CompletionItem) }
  end

  def definition_links(server, uri, source, line_token:, position_token: nil)
    position_token ||= line_token
    line = source.lines.index { |candidate| candidate.include?(line_token) }
    character = source.lines[line].index(position_token) + 1

    server.process_message({
      id: 1,
      method: "textDocument/definition",
      params: {textDocument: {uri: uri}, position: {line: line, character: character}}
    })

    pop_result(server).response.select { |item| item.is_a?(RubyLsp::Interface::LocationLink) }
  end

  # Hover at `position_token` on the first line containing `line_token`. Returns the markdown value, or nil.
  def hover_text(server, uri, source, line_token:, position_token: nil)
    position_token ||= line_token
    line = source.lines.index { |candidate| candidate.include?(line_token) }
    character = source.lines[line].index(position_token) + 1

    server.process_message({
      id: 1,
      method: "textDocument/hover",
      params: {textDocument: {uri: uri}, position: {line: line, character: character}}
    })

    pop_result(server).response&.contents&.value
  end

  # Code actions for a zero-width range at `position_token` on the first line containing `line_token`.
  def code_actions(server, uri, source, line_token:, position_token: nil)
    line = source.lines.index { |candidate| candidate.include?(line_token) }
    character = position_token ? source.lines[line].index(position_token) : 0
    position = {line: line, character: character}

    server.process_message({
      id: 1,
      method: "textDocument/codeAction",
      params: {
        textDocument: {uri: uri},
        range: {start: position, end: position},
        context: {diagnostics: []}
      }
    })

    Array(pop_result(server).response).select { |item| item.is_a?(RubyLsp::Interface::CodeAction) }
  end

  # Pull diagnostics for `uri` and return the LSP Diagnostic items from the full report.
  def diagnostic_items(server, uri)
    server.process_message({
      id: 1,
      method: "textDocument/diagnostic",
      params: {textDocument: {uri: uri}}
    })

    report = pop_result(server).response
    report.respond_to?(:items) ? report.items : []
  end

  def override_addon_settings(settings)
    addon = RubyLsp::Addon.addons.find { |candidate| candidate.name == "Ruby LSP YARD" }
    addon.define_singleton_method(:settings) { RubyLsp::Yard::Settings.new(settings) }
  end

  def label_details(item)
    item.attributes[:labelDetails]&.attributes || {}
  end
end
