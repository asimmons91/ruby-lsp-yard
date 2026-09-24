# Ruby LSP YARD

A [Ruby LSP](https://shopify.github.io/ruby-lsp/) add-on that treats YARD `@param`/`@return` tags as type
annotations, so completion, hover, signature help and go to definition work in untyped Ruby codebases that
carry thorough YARD documentation.

## Status

**M0 (foundation) is complete.** The add-on activates and shows up in Ruby LSP's add-on list, reads per-add-on
settings, logs through Ruby LSP's client notifications, and exposes the Indexer Adapter that every feature will
use. YARD parsing and editor features land in M1–M7; see [`docs/requirements_v1.md`](docs/requirements_v1.md)
for the full plan.

## Requirements

- Ruby >= 3.4
- Ruby LSP 0.26.x (`0.27`/Rubydex support is planned, see milestone M6)

## Installation

The gem is not published to RubyGems yet. Add it to your `Gemfile` from git:

```ruby
group :development do
  gem "ruby-lsp-yard", github: "asimmons91/ruby-lsp-yard", require: false
end
```

Run `bundle install` and restart the language server. Ruby LSP discovers the add-on automatically and lists it
as `Ruby LSP YARD`. If the installed Ruby LSP version is outside the supported range, the add-on is skipped
with a warning and the rest of Ruby LSP keeps working.

## Settings

Settings live under `rubyLsp.addonSettings`, keyed by the add-on name. For VS Code:

```json
{
  "rubyLsp.addonSettings": {
    "Ruby LSP YARD": {
      "logLevel": "info",
      "debugInference": false
    }
  }
}
```

| Setting | Default | Gates |
|---|---|---|
| `enableCompletion` | `true` | Type-aware method completion (M2) |
| `enableHover` | `true` | Documented types in hover (M1) |
| `enableSignatureHelp` | `true` | Parameter types in signature help (M1) |
| `enableDefinition` | `true` | Go to definition from YARD types (M2) |
| `enableInlayHints` | `false` | Inferred type hints (M2, if the add-on API allows) |
| `enableDiagnostics` | `true` | YARD diagnostics (M5) |
| `enableAuthoring` | `true` | YARD comment completion and skeletons (M4) |
| `logLevel` | `"info"` | One of `debug`, `info`, `warn`, `error` |
| `debugInference` | `false` | Logs how inference reached each result |

Feature toggles are already read during activation; the behavior they gate arrives in later milestones. Invalid
values fall back to the defaults, and no configuration is required at all.

## Development

```bash
bin/setup                                  # bundle install
bundle exec rake                           # tests + standard (what CI runs)
bundle exec rake test                      # tests only
BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.26.gemfile bundle exec rake   # a specific ruby-lsp version
```

- `Gemfile.common` holds the shared development dependencies; each `gemfiles/ruby_lsp_*.gemfile` pins one
  supported Ruby LSP minor. CI runs the matrix in `.github/workflows/main.yml`.
- All indexer access goes through `RubyLsp::Yard::Indexer::Adapter`. Backends are validated by the shared
  contract in `test/support/adapter_contract.rb`, which the Rubydex backend will reuse in M6.
- Fixture projects live in `test/fixtures/`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/asimmons91/ruby-lsp-yard.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RubyLsp::Yard project's codebases, issue trackers, chat rooms and mailing lists is
expected to follow the [code of conduct](https://github.com/asimmons91/ruby-lsp-yard/blob/main/CODE_OF_CONDUCT.md).
