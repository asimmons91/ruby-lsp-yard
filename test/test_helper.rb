# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ruby_lsp/internal"
require "ruby_lsp/test_helper"
require "ruby_lsp/ruby_lsp_yard/addon"

require_relative "support/adapter_contract"
require_relative "support/index_helpers"
require_relative "support/inference_helpers"
require_relative "support/lsp_helpers"
require_relative "support/diagnostics_helpers"

require "minitest/autorun"
