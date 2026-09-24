# frozen_string_literal: true

# Sends real LSP requests through Ruby LSP's test server and extracts the interesting part of the response, so the
# completion and definition listener tests stay close to what an editor would see.
module LspHelpers
  def index_fixtures(server)
    IndexHelpers::FIXTURE_FILES.each { |file| server.global_state.index.index_file(fixture_uri(file)) }
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

  def override_addon_settings(settings)
    addon = RubyLsp::Addon.addons.find { |candidate| candidate.name == "Ruby LSP YARD" }
    addon.define_singleton_method(:settings) { RubyLsp::Yard::Settings.new(settings) }
  end

  def label_details(item)
    item.attributes[:labelDetails]&.attributes || {}
  end
end
