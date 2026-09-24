# Ruby LSP YARD

A [Ruby LSP](https://shopify.github.io/ruby-lsp/) add-on that treats YARD `@param`/`@return` tags as type
annotations, so completion, hover, signature help and go to definition work in untyped Ruby codebases that
carry thorough YARD documentation.

## Status

**M0 (foundation) and M1 (YARD parsing, signature store, hover) are complete.** The add-on reads YARD `@param`
and `@return` tags through the `yard` gem's docstring parser and shows a typed signature on hover for receivers
Ruby LSP can already resolve: `self`, constants and `Foo.new`. Completion, inference, signature help and the
remaining features land in M2–M7; see [`docs/requirements_v1.md`](docs/requirements_v1.md) for the full plan.

Known gaps in M1:

- Signature help has no add-on hook in Ruby LSP 0.26 (`Requests::SignatureHelp` ignores add-ons), so the
  `enableSignatureHelp` setting is reserved until an upstream hook exists or a later milestone patches it.
- Hover on a type name inside a YARD comment needs the comment-reaching patch from M4 and is not available yet.
- Ruby LSP only target-hovers `CallNode` and the other node types in `Listeners::Hover::ALLOWED_TARGETS`, which
  excludes `def` nodes, so definitions are not enriched.

## Requirements

- Ruby >= 3.4
- Ruby LSP 0.26.x (`0.27`/Rubydex support is planned, see milestone M6)
- `yard` >= 0.9 (`~> 0.9`) is installed as a runtime dependency for docstring parsing only; the Registry,
  `yardoc` and HTML generation are never used

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
| `enableSignatureHelp` | `true` | Reserved: no add-on hook in Ruby LSP 0.26 (see Status) |
| `enableDefinition` | `true` | Go to definition from YARD types (M2) |
| `enableInlayHints` | `false` | Inferred type hints (M2, if the add-on API allows) |
| `enableDiagnostics` | `true` | YARD diagnostics (M5) |
| `enableAuthoring` | `true` | YARD comment completion and skeletons (M4) |
| `logLevel` | `"info"` | One of `debug`, `info`, `warn`, `error` |
| `debugInference` | `false` | Logs how inference reached each result |

Feature toggles are already read during activation; the behavior they gate arrives in later milestones. Invalid
values fall back to the defaults, and no configuration is required at all.

## Hover

Hovering a method call whose receiver type Ruby LSP can infer (`self`, a constant or `Foo.new`) adds a typed
signature built from YARD tags, for example:

```ruby
def fetch(key: Symbol, default = ...: String?, limit: ...: Integer, **options: Hash, &block) → Array<String>?
```

`@raise`, `@deprecated`, `@option`, `@yield`/`@yieldparam`/`@yieldreturn` and `@note`/`@see`/`@since`/`@api`
tags are appended below the signature, and every `@overload` is shown as its own signature. The prose docstring
is left to Ruby LSP itself so the two responses do not duplicate each other.

Methods whose docs only exist behind a `@!method`, `@!attribute` or `@!parse` directive are resolved too, as
are docstrings inherited through `include`, `extend` and superclasses and YARD `(see Foo#bar)` references.

## Development

```bash
bin/setup                                  # bundle install
bundle exec rake                           # tests + standard (what CI runs)
bundle exec rake test                      # tests only
bundle exec rake corpus                    # parse the YARD comments of installed top gems (NFR-T3)
BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.26.gemfile bundle exec rake   # a specific ruby-lsp version
```

- `Gemfile.common` holds the shared development dependencies; each `gemfiles/ruby_lsp_*.gemfile` pins one
  supported Ruby LSP minor. CI runs the matrix in `.github/workflows/main.yml`.
- All indexer access goes through `RubyLsp::Yard::Indexer::Adapter`. Backends are validated by the shared
  contract in `test/support/adapter_contract.rb`, which the Rubydex backend will reuse in M6.
- Fixture projects live in `test/fixtures/`.
- `rake corpus` scans the gems in `test/corpus/gems.txt` that are installed, reports the type expression failure
  rate and fails above `CORPUS_MAX_FAILURE_RATE` (default 1%). A scheduled GitHub workflow installs the list and
  runs it weekly.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/asimmons91/ruby-lsp-yard.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RubyLsp::Yard project's codebases, issue trackers, chat rooms and mailing lists is
expected to follow the [code of conduct](https://github.com/asimmons91/ruby-lsp-yard/blob/main/CODE_OF_CONDUCT.md).
