# frozen_string_literal: true

require_relative "lib/ruby_lsp_yard/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-lsp-yard"
  spec.version = RubyLsp::Yard::VERSION
  spec.authors = ["Austin Simmons"]
  spec.email = ["austin_simmons@fastmail.com"]

  spec.summary = "Ruby LSP add-on that reads YARD @param and @return tags as type annotations"
  spec.description = "Provides completion, hover, signature help and definition for Ruby LSP by " \
    "treating YARD @param, @return and related tags as type annotations."
  spec.homepage = "https://github.com/asimmons91/ruby-lsp-yard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/asimmons91/ruby-lsp-yard/blob/main/CHANGELOG.md"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml gemfiles/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependency for YARD docstring parsing only (D2). We use the `yard` gem's docstring parser and nothing
  # else: no Registry, no yardoc, no HTML generation.
  spec.add_dependency "yard", "~> 0.9"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
