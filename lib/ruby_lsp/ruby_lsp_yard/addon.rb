# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/addon"
require_relative "../../ruby_lsp_yard/version"

RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")

module RubyLsp
  module Yard
    class Addon < ::RubyLsp::Addon
      def activate(global_state, outgoing_queue)
      end

      def deactivate
      end

      def name
        "Ruby LSP YARD"
      end

      def version
        VERSION
      end
    end
  end
end
