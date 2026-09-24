# frozen_string_literal: true

require "language_server-protocol"
require "ruby_lsp/utils"

module RubyLsp
  module Yard
    # Logs through Ruby LSP's client notifications instead of `$stdout`, which would corrupt the LSP stream
    # (NFR-O1). Never raises, so a broken queue cannot take down a request (NFR-R2).
    class Log
      LEVELS = {debug: 0, info: 1, warn: 2, error: 3}.freeze
      PREFIX = "[Ruby LSP YARD]"

      def initialize(outgoing_queue, level: :info)
        @outgoing_queue = outgoing_queue
        @level = LEVELS.fetch(level, LEVELS[:info])
      end

      def debug(message)
        write(:debug, message)
      end

      def info(message)
        write(:info, message)
      end

      def warn(message)
        write(:warn, message)
      end

      def error(message)
        write(:error, message)
      end

      private

      def write(level, message)
        return if LEVELS.fetch(level) < @level

        @outgoing_queue << RubyLsp::Notification.window_log_message(
          "#{PREFIX} #{message}",
          type: message_type(level)
        )
      rescue
        nil
      end

      def message_type(level)
        case level
        when :error
          RubyLsp::Constant::MessageType::ERROR
        when :warn
          RubyLsp::Constant::MessageType::WARNING
        else
          RubyLsp::Constant::MessageType::LOG
        end
      end
    end
  end
end
