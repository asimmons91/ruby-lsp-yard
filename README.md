# Ruby LSP YARD

A [Ruby LSP](https://shopify.github.io/ruby-lsp/) add-on that treats YARD `@param`/`@return` tags as type
annotations, so completion, hover, signature help and go to definition work in untyped Ruby codebases that
carry thorough YARD documentation.

## Status

**M0 (foundation), M1 (YARD parsing, signature store, hover), M2 (inference, completion, definition), M3
(core/stdlib types, generics, gem caching) and M4 (YARD authoring) are complete.** The add-on reads YARD `@param`
and `@return` tags through the `yard` gem's docstring parser and infers receiver types from literals, constants,
`self`, method parameters, local and instance variable assignments, `Foo.new`, call chains, unions, duck types
and blocks. Core and stdlib signatures come from RBS, generic type variables are substituted at the call site,
and YARD comments in dependency gems are cached on disk. Inside comments, completion helps write tags, types and
parameters, hover and go to definition work on type names, and a code action inserts a comment skeleton.
Diagnostics and the Ruby 0.27 backend land in M5–M7; see
[`docs/requirements_v1.md`](docs/requirements_v1.md) for the full plan.

Known gaps:

- Signature help has no add-on hook in Ruby LSP 0.26 (`Requests::SignatureHelp` ignores add-ons), so the
  `enableSignatureHelp` setting is reserved until an upstream hook exists or a later milestone patches it.
- Inlay hints have no add-on hook either (`Requests::InlayHints` ignores add-ons), so `enableInlayHints` is
  reserved and FR-M2-20 is descoped until a hook appears.
- Ruby LSP only target-hovers `CallNode` and the other node types in `Listeners::Hover::ALLOWED_TARGETS`, which
  excludes `def` nodes, so definitions are not enriched.
- Comment authoring is a version-guarded patch (D3) and only activates on the Ruby LSP versions listed in
  `lib/ruby_lsp_yard/authoring/patch.rb`; any other version disables it with one warning while the rest of the
  add-on keeps working.
- Solargraph-style inline `# @type [Foo]` annotations are deferred to M7 (D6), and the per-file Sorbet policy in
  D5 cannot be applied because the completion and definition hooks do not receive the file's Sorbet level.
- `rbs collection` gem signatures (FR-M3-07) are deferred to M7; the RBS bridge covers core and stdlib only.
- RBS intersections are approximated as unions and records as hashes, and rbs gem signatures are not navigable
  targets (go to definition for core methods still points at the `rbs` gem's `.rbs` files through Ruby LSP).

## Requirements

- Ruby >= 3.4
- Ruby LSP 0.26.x (`0.27`/Rubydex support is planned, see milestone M6)
- `yard` >= 0.9 (`~> 0.9`) is installed as a runtime dependency for docstring parsing only; the Registry,
  `yardoc` and HTML generation are never used
- `rbs` >= 3, < 5 is installed as a runtime dependency for core/stdlib signatures; the RBS environment is built
  in a background thread and never blocks requests

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
| `enableCompletion` | `true` | Type-aware method completion |
| `enableHover` | `true` | Documented types in hover |
| `enableSignatureHelp` | `true` | Reserved: no add-on hook in Ruby LSP 0.26 (see Status) |
| `enableDefinition` | `true` | Go to definition from YARD types |
| `enableInlayHints` | `false` | Reserved: no add-on hook in Ruby LSP 0.26 (see Status) |
| `enableDiagnostics` | `true` | YARD diagnostics (M5) |
| `enableAuthoring` | `true` | YARD comment completion and skeletons (M4) |
| `enableSnippets` | `true` | Snippet placeholders in comment completion (`false` inserts plain text) |
| `enableCoreTypes` | `true` | RBS core/stdlib signatures and generics |
| `logLevel` | `"info"` | One of `debug`, `info`, `warn`, `error` |
| `debugInference` | `false` | Logs how inference reached each result |

Feature toggles are read during activation; invalid values fall back to the defaults, and no configuration is
required at all. Comment completion and skeletons require `enableAuthoring`; comment hover additionally requires
`enableHover` and comment definition `enableDefinition`.

## Hover

Hovering a method call whose receiver type Ruby LSP can infer (`self`, a constant or `Foo.new`) adds a typed
signature built from YARD tags, for example:

```ruby
def fetch(key: Symbol, default = ...: String?, limit: Integer = ..., **options: Hash, &block) → Array<String>?
```

`@raise`, `@deprecated`, `@option`, `@yield`/`@yieldparam`/`@yieldreturn` and `@note`/`@see`/`@since`/`@api`
tags are appended below the signature, and every `@overload` is shown as its own signature. The prose docstring
is left to Ruby LSP itself so the two responses do not duplicate each other.

Methods whose docs only exist behind a `@!method`, `@!attribute` or `@!parse` directive are resolved too, as
are docstrings inherited through `include`, `extend` and superclasses and YARD `(see Foo#bar)` references.

## Inference

Receiver types come from YARD tags and code (requirements FR-M2-01..13): literals, constants, `self` (including
`class << self`), `@param` tags, local variable assignments before the cursor, instance variables typed by
attribute docs or class assignments, `Foo.new` (respecting a documented `self.new`), call chains with
`@return [self]`, `@yieldparam` for block parameters, unions and `#duck` types. Inference stops after a 20 ms
budget or 8 chained calls and degrades to Ruby LSP's own behavior rather than guessing; `nil` is dropped from
unions and `Object` is treated as unknown (D7).

## Core and stdlib types

Core and stdlib signatures come from RBS (FR-M3-01). The environment (core plus every stdlib library shipped by
the `rbs` gem) is built in a background thread at activation, so the server keeps answering requests while it
loads; until it is ready, inference falls back to YARD and Ruby LSP. Where RBS and YARD both describe a method,
RBS wins (D5) — for example when a project reopens a core class with YARD docs.

Generics are substituted at the call site (FR-M3-02): `[1, 2].first` is `Integer`, `"a,b".split(",")` is
`Array<String>`, and `"a,b".split(",").map(&:strip)` is `Array<String>` (FR-M3-03 infers the block's return
type; both block bodies and `&:symbol` blocks are supported). `hash.each { |k, v| }` types both destructured
block parameters from the `Hash[K, V]#each` block signature. RBS interfaces such as `_ToS` become duck types,
and RBS aliases are expanded with a depth cap.

## Dependency gems

YARD comments in bundled gems are read lazily, the first time a method in them is resolved, and the built
signatures are persisted to a disk cache at `~/.cache/ruby-lsp-yard/<schema>/<gem>-<version>.bin` (FR-M3-05,
D9). The cache is shared across projects, keyed by gem name and version, and a change to `Gemfile.lock`
invalidates it. Writes are batched (the first signature for a gem is written immediately, later ones at most
every 32 writes or 2 seconds, plus on shutdown), and caching is independent of the `enableCoreTypes` setting.
Gems excluded from Ruby LSP's own indexing never reach the store, so they are excluded here too (FR-M3-06).
Loading `rbs collection` signatures (FR-M3-07) is deferred to M7.

## Completion

After `recv.`, completion offers the methods of the inferred type. Items carry the typed parameter list and
return type in their label details, the docstring summary as documentation, and are ranked with the receiver's
own class before its ancestors. Methods that exist on only part of a union are labeled with the member types that
provide them, and duck types offer exactly the documented methods. Private and protected methods are offered only
for internal receivers. Items that the add-on can enrich replace Ruby LSP's untyped items for the same method, so
plain Ruby LSP and ruby-lsp-rails users see no duplicates. When the receiver type is unknown, the add-on emits
nothing and Ruby LSP's own behavior applies.

## Go to definition

For `recv.m` whose receiver type is inferred from YARD — including parameters, locals, instance variables and
chains — go to definition jumps to the definitions of `m` on the receiver's ancestors, including `extend`ed
modules. When the add-on knows the receiver, its precise targets replace Ruby LSP's fallback of listing every
method with that name; when it does not, the host response is left untouched.

## YARD authoring

Inside a YARD comment, the add-on offers tag, directive, type and parameter completion (FR-M4-01..05). Typing
`# @ret` and accepting `@return` produces `# @return [Type]` with the type placeholder selected. `@param`
suggestions are generated from the definition below and skip parameters that already have a tag; `@yield*` is
only suggested for methods that yield or take a `&block`, and `@raise` is prefilled with the class of the first
`raise SomeError` in the body. Inside `[...]`, constants come from the workspace index, resolved relative to the
definition's nesting, alongside YARD's special names and snippets for `Array<T>`, `Hash{K => V}`, `Tuple(a, b)`
and `Class<T>`.

Because add-ons cannot register trigger characters, `[` does not open completion by itself; type completion
needs Ctrl+Space. VS Code additionally disables as-you-type suggestions inside comments by default, so turn on
`editor.quickSuggestions.comments` (or press Ctrl+Space) to see suggestions as you type (FR-M4-07).

Hovering a type name inside a comment shows that class's documentation, and go to definition jumps to it
(FR-M1-14, FR-M4-P6). A code action on an undocumented `def` inserts a full comment skeleton — a summary
placeholder, one `@param` per parameter, `@yield*` when the method yields and `@return` — with types prefilled
from inherited or overridden documentation when available (FR-M4-06).

Comment support is a version-guarded patch (D3). It is only applied to the Ruby LSP versions listed in
`lib/ruby_lsp_yard/authoring/patch.rb`; on any other version the add-on logs one warning and leaves Ruby LSP's
behavior untouched. Comment completion uses snippet placeholders when the editor reports snippet support; Ruby
LSP 0.26 applies client capabilities before add-ons load, so the capability is usually unknown and the add-on
assumes support. Clients without snippets support can set `enableSnippets` to `false` to insert plain text
(NFR-C3).

## Development

```bash
bin/setup                                  # bundle install
bundle exec rake                           # tests + standard (what CI runs)
bundle exec rake test                      # tests only
bundle exec rake corpus                    # parse the YARD comments of installed top gems (NFR-T3)
bundle exec rake benchmark                 # inference, completion and RBS latency (NFR-P2/P3)
BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.26.gemfile bundle exec rake   # a specific ruby-lsp version
```

- `Gemfile.common` holds the shared development dependencies; each `gemfiles/ruby_lsp_*.gemfile` pins one
  supported Ruby LSP minor. CI runs the matrix in `.github/workflows/main.yml`.
- All indexer access goes through `RubyLsp::Yard::Indexer::Adapter`. Backends are validated by the shared
  contract in `test/support/adapter_contract.rb`, which the Rubydex backend will reuse in M6.
- `lib/ruby_lsp_yard/rbs/` loads RBS core/stdlib signatures in the background and converts them to the internal
  type model; `lib/ruby_lsp_yard/gems/` locates gem files and caches their parsed signatures.
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
