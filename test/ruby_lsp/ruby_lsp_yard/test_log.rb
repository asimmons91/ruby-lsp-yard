# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Yard
    class TestLog < Minitest::Test
      def test_writes_window_log_messages_to_the_outgoing_queue
        queue = Thread::Queue.new
        log = Log.new(queue, level: :debug)

        log.error("something broke")

        message = queue.pop
        assert_equal "window/logMessage", message.method
        assert_equal "[Ruby LSP YARD] something broke", message.params.message
        assert_equal RubyLsp::Constant::MessageType::ERROR, message.params.type
      end

      def test_respects_the_configured_level
        queue = Thread::Queue.new
        log = Log.new(queue, level: :warn)

        log.info("not interesting")
        log.debug("not interesting either")

        assert queue.empty?
      end

      def test_defaults_to_info_level
        queue = Thread::Queue.new
        log = Log.new(queue)

        log.debug("not interesting")
        assert queue.empty?

        log.info("interesting")
        assert_equal "window/logMessage", queue.pop.method
      end

      def test_never_raises_when_the_queue_fails
        log = Log.new(Object.new)

        assert_nil log.info("boom")
      end
    end
  end
end
