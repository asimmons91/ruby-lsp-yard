# frozen_string_literal: true

require_relative "../types"
require_relative "rules"

module RubyLsp
  module Yard
    module Diagnostics
      # FR-M5-03 (D10): quick fixes for the fixable diagnostics of a document. Ruby LSP 0.26 has no add-on
      # code-action hook, so the M4 `Requests::CodeActions` patch appends these actions to the host response.
      #
      # Fixes are derived from freshly computed diagnostics rather than from the diagnostic objects the client
      # echoes back, so they stay correct when the buffer changed after the diagnostic was published.
      class Fixes
        # Names more than this many edits apart are not considered a likely match.
        MAX_DISTANCE = 2
        CANDIDATE_CAP = 250
        PARAM_PREFIX = "@param "

        def initialize(linter:, adapter: nil, store: nil, log: nil)
          @linter = linter
          @adapter = adapter
          @store = store
          @log = log
        end

        # Actions whose diagnostic range intersects the requested LSP range. `range` may be an
        # `Interface::Range` or the raw params hash the host passes to `Requests::CodeActions`. Suppressed
        # findings offer no action (FR-M5-02).
        def actions_for(document:, uri:, range:)
          range = normalize_range(range)
          return [] unless @linter && range

          diagnostics = Array(@linter.diagnostics_for(document))
          diagnostics
            .reject { |diagnostic| @linter.suppressed?(diagnostic) }
            .select { |diagnostic| intersects?(diagnostic.range, range) }
            .filter_map { |diagnostic| action_for(diagnostic, document, uri) }
        rescue => e
          @log&.error("Quick fixes failed: #{e.class}: #{e.message}")
          []
        end

        private

        def normalize_range(range)
          return range if range.respond_to?(:start) && range.respond_to?(:end)
          return nil unless range.is_a?(Hash)

          from = range[:start] || range["start"]
          to = range[:end] || range["end"]
          return nil unless from && to

          Interface::Range.new(
            start: normalize_position(from),
            end: normalize_position(to)
          )
        rescue
          nil
        end

        def normalize_position(position)
          Interface::Position.new(
            line: position[:line] || position["line"],
            character: position[:character] || position["character"]
          )
        end

        def action_for(diagnostic, document, uri)
          case diagnostic.rule
          when Rules::UnknownParam.key
            rename_param(diagnostic, document, uri)
          when Rules::MissingParam.key
            add_param(diagnostic, document, uri)
          when Rules::UnresolvedType.key
            fix_type_name(diagnostic, document, uri)
          end
        end

        # Rename `@param name` to the closest parameter the method actually has.
        def rename_param(diagnostic, document, uri)
          tag = diagnostic.data[:param].to_s
          return nil if tag.empty?

          text = text_at(document, diagnostic.range)
          return nil unless text.start_with?("@param #{tag}")

          candidates = diagnostic.target.parameters.map { |parameter| parameter.name.to_s }
          match = closest(tag, candidates)
          return nil unless match

          start = diagnostic.range.start.character + PARAM_PREFIX.length
          edit_range = range_at(diagnostic.range.start.line, start, start + tag.length)
          action("Rename `@param #{tag}` to `@param #{match}`", uri, edit_range, match)
        end

        # Add the missing `@param` tag at the end of the comment block, with the type from inherited documentation
        # when the signature store knows it.
        def add_param(diagnostic, document, uri)
          name = diagnostic.data[:parameter].to_s
          return nil if name.empty?

          target = diagnostic.target
          return nil unless target

          line = target.comment_start_line - 1 + target.comment_lines.size
          indent = comment_indent(document, target)
          new_text = "#{indent}# @param #{name} [#{param_type(target, name)}]\n"
          action("Add `@param #{name}`", uri, range_at(line, 0, 0), new_text)
        end

        # Fix the spelling of an unresolved type name using the closest indexed constant.
        def fix_type_name(diagnostic, document, uri)
          name = diagnostic.data[:name].to_s
          return nil if name.empty?
          return nil unless text_at(document, diagnostic.range) == name

          candidate = closest(name, type_candidates(name, diagnostic.target))
          return nil unless candidate

          action("Change `#{name}` to `#{candidate}`", uri, diagnostic.range, candidate)
        end

        # --- Helpers -----------------------------------------------------------------------------------------------

        def param_type(target, name)
          type = typed_param(lookup_signature(target), name)
          type ||= inherited_param_type(target, name)
          type ? Types::Formatter.format(type) : "Type"
        rescue
          "Type"
        end

        def inherited_param_type(target, name)
          return nil unless @adapter && !target.owner.to_s.empty?

          @adapter.ancestors(target.owner).each do |ancestor|
            next if ancestor == target.owner

            signature = @store&.lookup(ancestor, target.name, singleton: target.singleton)
            type = typed_param(signature, name)
            return type if type
          end
          nil
        rescue
          nil
        end

        def typed_param(signature, name)
          parameter = signature&.params&.find { |candidate| candidate.name.to_s == name }
          return nil unless parameter&.typed?

          parameter.types
        end

        def lookup_signature(target)
          return nil unless @store && target.owner && !target.owner.empty?

          @store.lookup(target.owner, target.name, singleton: target.singleton)
        rescue
          nil
        end

        # Candidate constant names, shortened relative to the documented definition's nesting. The prefix is the
        # first character of the misspelling, so the candidate set stays bounded regardless of the prefix tree.
        def type_candidates(name, target)
          return [] unless @adapter && target

          nesting = Array(target.nesting)
          candidates = @adapter.constant_candidates(name[0].to_s, nesting).first(CANDIDATE_CAP)
          candidates.map { |definition| relative_name(definition.name.to_s, nesting) }.uniq
        rescue
          []
        end

        def relative_name(full_name, nesting)
          nesting.length.downto(1) do |size|
            namespace = nesting[0...size].join("::")
            return full_name.delete_prefix("#{namespace}::") if full_name.start_with?("#{namespace}::")
          end
          full_name
        end

        # The closest candidate within {MAX_DISTANCE} edits. A tie for the best distance makes the choice ambiguous
        # and no fix is offered.
        def closest(name, candidates)
          best = nil
          best_distance = nil
          candidates.each do |candidate|
            next if candidate == name || candidate.empty?

            distance = edit_distance(name, candidate)
            next if distance > MAX_DISTANCE

            if best_distance.nil? || distance < best_distance
              best = candidate
              best_distance = distance
            elsif distance == best_distance
              best = nil
            end
          end
          best
        end

        # Levenshtein distance between two names.
        def edit_distance(left, right)
          return right.length if left.empty?
          return left.length if right.empty?

          previous = (0..right.length).to_a
          left.each_char.with_index(1) do |left_char, row|
            current = [row]
            right.each_char.with_index(1) do |right_char, column|
              current[column] = [
                current[column - 1] + 1,
                previous[column] + 1,
                previous[column - 1] + ((left_char == right_char) ? 0 : 1)
              ].min
            end
            previous = current
          end
          previous.last
        end

        def comment_indent(document, target)
          line = document.source.lines[target.comment_start_line - 1].to_s
          line[/\A[ \t]*/].to_s
        end

        def text_at(document, range)
          return nil unless range&.start && range.end

          line = document.source.lines[range.start.line].to_s
          line[range.start.character...range.end.character]
        rescue
          nil
        end

        def intersects?(left, right)
          return false unless left && right

          position_compare(left.start, right.end) <= 0 && position_compare(right.start, left.end) <= 0
        end

        def position_compare(left, right)
          comparison = left.line <=> right.line
          comparison.zero? ? (left.character <=> right.character) : comparison
        end

        def range_at(line, start_character, end_character)
          Interface::Range.new(
            start: Interface::Position.new(line: line, character: start_character),
            end: Interface::Position.new(line: line, character: end_character)
          )
        end

        def action(title, uri, range, new_text)
          Interface::CodeAction.new(
            title: title,
            kind: Constant::CodeActionKind::QUICK_FIX,
            edit: Interface::WorkspaceEdit.new(
              changes: {uri.to_s => [Interface::TextEdit.new(range: range, new_text: new_text)]}
            )
          )
        end
      end
    end
  end
end
