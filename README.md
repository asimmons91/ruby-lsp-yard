# Ruby LSP YARD

A [Ruby LSP](https://shopify.github.io/ruby-lsp/) add-on that treats YARD `@param`/`@return` tags as type
annotations, so completion, hover and go to definition work in untyped Ruby codebases that carry thorough YARD
documentation. Core and standard library signatures come from RBS, and YARD, RBS and `rbs-inline` types are
resolved through one shared signature store.

## Features

- **Type-aware completion, hover and go to definition** driven by YARD tags, with typed signatures, docstring
  summaries and ancestor-aware ranking.
- **Inference** from literals, constants, `self`, method parameters, local and instance variable assignments,
  `Foo.new`, call chains, unions, duck types and blocks.
- **RBS core and stdlib types**, including generics substituted at the call site; YARD comments in dependency
  gems are parsed lazily and cached on disk.
- **YARD authoring**: tag, directive, type and parameter completion inside comments, hover and go to definition
  on type names, and a code action that inserts a comment skeleton.
- **Diagnostics** for broken or inconsistent YARD documentation, with configurable severities and quick fixes.
- **DSL support** through `@!macro` expansions and `@!domain` completion.
- **Solargraph compatibility**: `.solargraph.yml` domains and inline `# @type [Foo]` annotations.
- **Extra RBS sources**: `rbs collection` and `rbs-inline` (`#:`/`@rbs`) signatures.
- **Both Ruby LSP indexers**: works on Ruby LSP 0.26 (`RubyIndexer`) and 0.27 (`Rubydex`) through the same
  indexer adapter.

## Prerequisites

- Ruby >= 3.4
- Ruby LSP 0.26.x (`RubyIndexer`) or 0.27.x (`Rubydex`); the supported range is `< 0.28.0`, and the add-on is
  skipped with a warning outside of it
- The runtime dependencies (`yard ~> 0.9`, `rbs ~> 4.0` and `rbs-inline ~> 0.14`) are installed with the gem.
  `yard` is used for docstring parsing only: its Registry, `yardoc` and HTML generation are never used.
- The RBS environment is built in a background thread and never blocks requests.

## Installation

The gem is not published to RubyGems yet. Add it to your `Gemfile` from git:

```ruby
group :development do
  gem "ruby-lsp-yard", github: "asimmons91/ruby-lsp-yard", require: false
end
```

Run `bundle install` and restart the language server. Ruby LSP discovers the add-on automatically and lists it
as `Ruby LSP YARD`.

## Configuration

Settings live under `rubyLsp.addonSettings`, keyed by the add-on's settings key (`rubyLspYard`). For VS Code:

```json
{
  "rubyLsp.addonSettings": {
    "rubyLspYard": {
      "logLevel": "info",
      "debugInference": false
    }
  }
}
```

| Setting | Default | Description |
|---|---|---|
| `enableCompletion` | `true` | Type-aware method completion |
| `enableHover` | `true` | Documented types in hover |
| `enableSignatureHelp` | `true` | Reserved: no add-on hook in the supported Ruby LSP versions |
| `enableDefinition` | `true` | Go to definition from YARD types |
| `enableInlayHints` | `false` | Reserved: no add-on hook in the supported Ruby LSP versions |
| `enableDiagnostics` | `true` | YARD diagnostics; also requires `"yard"` in `rubyLsp.linters` |
| `diagnosticRules` | `{}` | Per-rule severities (`"error"`, `"warning"`, `"info"`, `"hint"`) or `false`/`"off"` to disable a rule |
| `enableAuthoring` | `true` | YARD comment completion and skeletons, and diagnostics quick fixes |
| `enableSnippets` | `true` | Snippet placeholders in comment completion (`false` inserts plain text) |
| `enableCoreTypes` | `true` | RBS core/stdlib signatures, `rbs collection` and generics |
| `enableMacros` | `true` | `@!macro` expansion at DSL call sites |
| `enableDomains` | `true` | `@!domain` and `.solargraph.yml` domains in implicit-`self` completion |
| `enableSolargraph` | `true` | Reading `.solargraph.yml` |
| `enableInlineTypes` | `true` | `rbs-inline` `#:`/`@rbs` annotations |
| `logLevel` | `"info"` | One of `debug`, `info`, `warn`, `error` |
| `debugInference` | `false` | Logs how inference reached each result |

Feature toggles are read during activation; invalid values fall back to the defaults, and no configuration is
required at all. Comment completion and skeletons require `enableAuthoring`; comment hover additionally requires
`enableHover` and comment definition `enableDefinition`.

Because add-ons cannot register trigger characters, `[` does not open completion by itself; type completion
needs Ctrl+Space. VS Code additionally disables as-you-type suggestions inside comments by default, so turn on
`editor.quickSuggestions.comments` (or press Ctrl+Space) to see suggestions as you type.

## Diagnostics

Ruby LSP does not auto-detect add-on linters, so diagnostics need one extra setting:

```json
{
  "rubyLsp.linters": ["rubocop", "yard"],
  "rubyLsp.addonSettings": {
    "rubyLspYard": {
      "enableDiagnostics": true,
      "diagnosticRules": {
        "YARD/MissingParam": "warning",
        "YARD/ArgumentTypeMismatch": false
      }
    }
  }
}
```

| Rule | Default | Description |
|---|---|---|
| `YARD/UnknownParam` | warning | A `@param` names a parameter the method doesn't have |
| `YARD/UnresolvedType` | warning | A type name doesn't resolve to a known constant |
| `YARD/InvalidTypeSyntax` | error | A type expression can't be parsed |
| `YARD/DuplicateTag` | warning | A `@param` or `@return` appears twice (outside an `@overload`) |
| `YARD/InvalidDirective` | error | A directive is malformed, or its `@!parse` text has a Ruby syntax error |
| `YARD/YieldWithoutBlock` | info | `@yield*` on a method that neither yields nor takes a block |
| `YARD/MissingParam` | off | A parameter has no `@param` tag (reported only on documented methods) |
| `YARD/MissingReturn` | off | A public method has no `@return` |
| `YARD/ArgumentTypeMismatch` | off | A literal argument's type conflicts with the `@param` type |
| `YARD/ReturnTypeMismatch` | off | A literal return value conflicts with `@return` |

The two mismatch rules only check literals against signatures built from YARD tags, so RBS-backed core and
stdlib methods are never reported; `Object`, `self`, `void`, duck types and type variables are treated as
unknown. Rules with a default of "off" run as soon as `diagnosticRules` gives them a severity.

Suppress rules per definition by adding `# yard:disable` to its comment block:

```ruby
# @param name [String]
# yard:disable YARD/UnresolvedType
def greet(name)
  ...
end
```

With no rule names the directive suppresses every rule for that definition; a file-level form does not exist.
Suppression applies to diagnostics attached to that definition, so it does not silence the mismatch rules for
call sites elsewhere.

Diagnostics are pulled by the editor on open and save, and after changes while the document is within Ruby
LSP's expensive-feature limit. The add-on enforces its own budget (100 ms per document): the syntax and
documentation rules always run, while the expensive type-mismatch rules are skipped once the budget is used up.

Where the API allows, diagnostics come with quick fixes (through the same version-guarded code-action patch as
authoring): rename an `@param` to the closest parameter, add a missing `@param` tag (types are prefilled from
inherited documentation when available), or replace an unresolved type name with the closest indexed constant.
Quick fixes require both `enableDiagnostics` and `enableAuthoring`.

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

## Comment authoring

Inside a YARD comment, the add-on offers tag, directive, type and parameter completion. Typing `# @ret` and
accepting `@return` produces `# @return [Type]` with the type placeholder selected. `@param` suggestions are
generated from the definition below and skip parameters that already have a tag; `@yield*` is only suggested for
methods that yield or take a `&block`, and `@raise` is prefilled with the class of the first `raise SomeError` in
the body. Inside `[...]`, constants come from the workspace index, resolved relative to the definition's
nesting, alongside YARD's special names and snippets for `Array<T>`, `Hash{K => V}`, `Tuple(a, b)` and
`Class<T>`.

Hovering a type name inside a comment shows that class's documentation, and go to definition jumps to it. A code
action on an undocumented `def` inserts a full comment skeleton — a summary placeholder, one `@param` per
parameter, `@yield*` when the method yields and `@return` — with types prefilled from inherited or overridden
documentation when available.

Comment completion uses snippet placeholders when the editor reports snippet support; Ruby LSP applies client
capabilities before add-ons load, so the capability is usually unknown and the add-on assumes support. Clients
without snippets support can set `enableSnippets` to `false` to insert plain text.

## Inference

Receiver types come from YARD tags and code: literals, constants, `self` (including `class << self`), `@param`
tags, local variable assignments before the cursor, instance variables typed by attribute docs or class
assignments, `Foo.new` (respecting a documented `self.new`), call chains with `@return [self]`, `@yieldparam`
for block parameters, unions and `#duck` types. Inference stops after a 20 ms budget or 8 chained calls and
degrades to Ruby LSP's own behavior rather than guessing; `nil` is dropped from unions and `Object` is treated
as unknown.

## Core, stdlib and dependency gem types

Core and stdlib signatures come from RBS. The environment (core plus every stdlib library shipped by the `rbs`
gem) is built in a background thread at activation, so the server keeps answering requests while it loads; until
it is ready, inference falls back to YARD and Ruby LSP. Where RBS and YARD both describe a method, RBS wins — for
example when a project reopens a core class with YARD docs.

Generics are substituted at the call site: `[1, 2].first` is `Integer`, `"a,b".split(",")` is `Array<String>`,
and `"a,b".split(",").map(&:strip)` is `Array<String>` (the block's return type is inferred; both block bodies
and `&:symbol` blocks are supported). `hash.each { |k, v| }` types both destructured block parameters from the
`Hash[K, V]#each` block signature. RBS interfaces such as `_ToS` become duck types, and RBS aliases are expanded
with a depth cap.

YARD comments in bundled gems are read lazily, the first time a method in them is resolved, and the built
signatures are persisted to a disk cache at `~/.cache/ruby-lsp-yard/<schema>/<gem>-<version>.bin`. The cache is
shared across projects, keyed by gem name and version, and a change to `Gemfile.lock` invalidates it. Writes are
batched (the first signature for a gem is written immediately, later ones at most every 32 writes or 2 seconds,
plus on shutdown), and caching is independent of the `enableCoreTypes` setting. Gems excluded from Ruby LSP's
own indexing never reach the store, so they are excluded here too.

## Macros and domains

`@!macro` directives are expanded into definitions. Named macros (`@!macro returnself` plus `@macro returnself`
invocations), `[new]` macros and `[attach]` macros are supported, with YARD's positional interpolation: `$0`–`$N`,
`${N-M}` ranges (including negative indexes), `$*` for the full DSL call and `\$` to escape. A macro is applied
only to calls that resolve to the method where the macro was defined, so attach macros defined on a class method
apply to subclass DSL calls, and macros are found through `include`, `extend` and superclasses. Macros that
reference other macros expand recursively with cycle detection. Only expansions containing `@!method`,
`@!attribute` or `@!parse` produce new methods or attributes; those definitions then flow into completion, hover
and go to definition like indexed ones. For example:

```ruby
class Resource
  # @!macro [attach] property
  #   @!method $1
  #     @return [$2] the $1 property
  def self.property(name, type); end
end

class Post < Resource
  property :title, String
end
# Post.new.title is now typed String
```

`@!domain` binds a DSL namespace to a class or module: inside it, the domain's methods are offered as
implicit-`self` completions. `Class<X>` domains contribute `X`'s class methods, plain `X` its instance methods.
The `.solargraph.yml` `domains` list applies the same binding workspace-wide.

## Solargraph compatibility

`.solargraph.yml` at the workspace root is read for its `domains` and `require` hints (`enableSolargraph`). The
file is re-read when its modification time changes. `require` hints are informational: the host index still
decides what is available, because the add-on does not parse required files itself.

Inline `# @type [Foo]` annotations type local and instance variable assignments:

```ruby
# @type [FixtureProject::Documented]
doc = unknown_builder
doc. # => Documented# methods
```

Annotations are read from the live document through the comment patch, so they work in unsaved buffers; without
the patch the assignment falls back to ordinary inference. The annotation on an assignment replaces that
assignment's inferred type, and unions (`# @type [Foo, nil]`) are supported.

## rbs collection and rbs-inline

When the workspace has an `rbs collection` (`rbs_collection.yaml` plus its lockfile), the loader adds the
collection's signatures to the background RBS environment automatically. Collection signatures follow the same
precedence as core RBS: where they and YARD both describe a method, RBS wins.

`rbs-inline` annotations are a second source of RBS types. Files that opt in with `# rbs_inline: enabled` have
their `#:` comments and `@rbs` tags parsed lazily, and the resulting signatures outrank the file's own YARD
comments:

```ruby
# rbs_inline: enabled
class Person
  attr_reader :name #: String

  # @rbs (Integer times) -> String
  def repeat(times) = "x" * times
end
```

Set `enableInlineTypes` to `false` to ignore these annotations.

## Limitations

- Ruby LSP does not auto-detect add-on linters, so diagnostics only run after `"yard"` is listed in
  `rubyLsp.linters` (see [Diagnostics](#diagnostics)).
- Diagnostics quick fixes and the comment skeleton rely on the version-guarded code-action patch, so they
  require `enableAuthoring` as well as `enableDiagnostics`.
- `YARD/MissingParam`, `YARD/MissingReturn`, `YARD/ArgumentTypeMismatch` and `YARD/ReturnTypeMismatch` are off by
  default; enable them through `diagnosticRules`.
- Signature help has no add-on hook in the supported Ruby LSP versions (`Requests::SignatureHelp` ignores
  add-ons), so the `enableSignatureHelp` setting is reserved until an upstream hook exists.
- Inlay hints have no add-on hook either (`Requests::InlayHints` ignores add-ons), so `enableInlayHints` is
  reserved.
- Ruby LSP only target-hovers the node types in `Listeners::Hover::ALLOWED_TARGETS`, which excludes `def` nodes,
  so definitions are not enriched.
- Comment authoring is a version-guarded patch and only activates on the Ruby LSP versions listed in
  `lib/ruby_lsp_yard/authoring/patch.rb`; any other version disables it with one warning while the rest of the
  add-on keeps working. Inline `@type` annotations are read through the same patch, so they are inactive there
  too.
- The per-file Sorbet policy cannot be applied because the completion and definition hooks do not receive the
  file's Sorbet level.
- Named macros defined only inside dependency gems are not discovered for invocation in workspace docstrings;
  attach macros still resolve through the index. Macro-generated methods reflect saved files (the current buffer
  is used only where inference runs on it).
- `.solargraph.yml` is not covered by Ruby LSP's `**/*.rb` file watcher, so changes are picked up when the
  add-on re-checks the file (mtime) rather than immediately. `require` hints are read but informational: the
  host index decides what is available.
- `rbs-inline` support follows the `rbs-inline` gem's parser output, so undocumented corners of that syntax
  (e.g. non-`def` DSLs) are not interpreted.
- RBS intersections are approximated as unions and records as hashes, and `rbs` gem signatures are not
  navigable targets (go to definition for core methods still points at the `rbs` gem's `.rbs` files through
  Ruby LSP).

## Development

```bash
bin/setup                                  # bundle install
bundle exec rake                           # tests + standard (what CI runs)
bundle exec rake test                      # tests only
bundle exec rake corpus                    # parse the YARD comments of installed top gems
bundle exec rake benchmark                 # inference, completion and RBS latency
BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.26.gemfile bundle exec rake   # a specific ruby-lsp version
BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.27.gemfile bundle exec rake   # the Rubydex backend
```

- `Gemfile.common` holds the shared development dependencies; each `gemfiles/ruby_lsp_*.gemfile` pins one
  supported Ruby LSP minor. CI runs the matrix in `.github/workflows/main.yml`.
- All indexer access goes through `RubyLsp::Yard::Indexer::Adapter`. Both backends (`RubyIndexer` for 0.26,
  `Rubydex` for 0.27) are validated by the shared contract in `test/support/adapter_contract.rb`.
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
