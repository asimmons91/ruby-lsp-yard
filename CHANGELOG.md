## [Unreleased]

- M7: expand `@!macro` DSL definitions — named, `[new]` and `[attach]` macros, YARD positional interpolation (`$0`,
  `$1`, ranges, `$*`, escaping), inheritance through `include`/`extend`/superclasses, recursive expansion with
  cycle detection, and only `@!method`/`@!attribute`/`@!parse` producing definitions (FR-M7-01)
- M7: apply `@!domain` (and `.solargraph.yml` `domains`) as implicit-`self` completions inside the namespace,
  with `Class<X>` resolved as a class context and plain `X` as an instance context (FR-M7-02)
- M7: read `.solargraph.yml` `domains` and `require` hints from the workspace root, refreshing when the file
  changes (FR-M7-03)
- M7: support Solargraph-style inline `# @type [Foo]` annotations above local and instance variable assignments
  through the live document, so unsaved buffers are typed correctly (FR-M2-13, D6)
- M7: load `rbs collection` signatures automatically when the workspace has one, so collection RBS wins over YARD
  like core RBS does (FR-M3-07)
- M7: support `rbs-inline` (`#:` comments and `@rbs` tags) as a second source of RBS types via a new runtime
  dependency; inline signatures outrank YARD comments (FR-M7-04, D5). The `rbs` dependency is now `~> 4.0`
- M7: add `enableMacros`, `enableDomains`, `enableSolargraph` and `enableInlineTypes` settings; complete
  `@!macro` and `@!domain` in comment directive completion
- M5: report broken or inconsistent YARD documentation through Ruby LSP's linter registration as the `"yard"`
  linter, with `YARD/UnknownParam`, `YARD/UnresolvedType`, `YARD/InvalidTypeSyntax`, `YARD/DuplicateTag`,
  `YARD/InvalidDirective` and `YARD/YieldWithoutBlock` on by default (FR-M5-01, FR-M5-04)
- M5: scan the live document once — methods, attributes, namespaces and constants with their comment blocks —
  tracking nesting, visibility and class-level DSL blocks, and never parse prose-only comments (NFR-P5)
- M5: add the off-by-default `YARD/MissingParam`, `YARD/MissingReturn`, `YARD/ArgumentTypeMismatch` and
  `YARD/ReturnTypeMismatch` rules, with light type checking restricted to literal arguments and returns against
  YARD-sourced signatures (`Signature#source`; the gem cache schema version is bumped)
- M5: configure each rule's severity or turn it off through the `diagnosticRules` add-on setting, and suppress
  rules per definition with `# yard:disable` (FR-M5-01/02, D10)
- M5: run diagnostics within a 100 ms budget so the expensive type checks never block the server (FR-M5-04)
- M5: extend the code-action patch with diagnostics quick fixes — rename an unknown `@param` to the closest
  parameter, add missing `@param` tags with inherited types when available, and fix unresolved type names
  (FR-M5-03)
- M4: complete YARD tags, directives, type names and parameter names inside comments through a version-guarded
  patch of Ruby LSP's completion request, with snippet placeholders when the client supports them (FR-M4-01..05,
  D3)
- M4: base tag suggestions on the definition below the comment — one `@param` per undocumented parameter,
  `@yield*` only for yielding methods and `@raise` prefilled with the first raised class (FR-M4-03)
- M4: complete type names inside `[...]` through a new adapter operation that resolves constants relative to the
  definition's nesting, alongside YARD specials and generic snippets (FR-M4-05)
- M4: show class documentation on hover and jump to definition for type names inside comments (FR-M1-14,
  FR-M4-P6)
- M4: add a code action that inserts a YARD comment skeleton for an undocumented `def`, with types prefilled
  from inherited documentation (FR-M4-06)
- M4: disable comment authoring with one warning on Ruby LSP versions outside the tested list, add the
  `enableSnippets` setting to fall back to plain text, and document the trigger-character and quick-suggestion
  limits (FR-M4-P2, NFR-C3, FR-M4-07)
- M3: load RBS core and stdlib signatures in a background thread and convert them into the internal type model
  (overloads, generics, block signatures, optional/keyword parameters, interfaces as duck types); `rbs` is now an
  explicit runtime dependency (FR-M3-01)
- M3: substitute RBS type variables at the call site — `[1, 2].first` → `Integer`, `"a,b".split(",")` →
  `Array<String>` — and prefer RBS signatures over YARD for core/stdlib owners (FR-M3-02, FR-M3-04)
- M3: infer block return types for `Array#map` with block bodies and `&:symbol` blocks (`map(&:strip)` →
  `Array<String>`), and destructure `Hash#each`'s tuple yield into `|k, v|` (FR-M3-03)
- M3: hash literals carry key/value unions so RBS generics bind (`{a: 1}` is `Hash[Symbol, Integer]`), and hover
  and completion label details render substituted generics (FR-M3-02)
- M3: parse YARD comments in dependency gems lazily and persist built signatures to a shared
  `~/.cache/ruby-lsp-yard/<schema>/` cache keyed by gem name/version, invalidated by a `Gemfile.lock` digest
  (FR-M3-05, FR-M3-06, D9)
- M3: add the `enableCoreTypes` setting, the M3 acceptance corpus, RBS/gem unit tests, core completion and hover
  integration tests, and `benchmark/rbs.rb`
- M3: record the implementation notes in `docs/requirements_v1.md` §8.1; FR-M3-07 (`rbs collection`) is deferred
- M2: infer receiver types from literals, constants, `self`, `@param` types, local assignments, instance variables,
  `Foo.new`, call chains (`@return [self]`), `@yieldparam` block parameters, unions and duck types, with a fixed
  20 ms/8-call budget and Unknown fallbacks
- M2: add type-aware method completion with typed label details, return types, eager documentation, union member
  labels and class-first ranking; enriched items replace Ruby LSP's untyped items for the same method (FR-M2-14..18)
- M2: add go to definition for YARD-typed receivers, narrowing Ruby LSP's fallback list of same-named methods
  (FR-M2-19)
- M2: extend the indexer adapter with comment-free completion candidates, full definition locations and file names
- M2: add the M2 completion corpus (≥ 90% accuracy), inference/completion benchmarks, and engine, scope, budget,
  completion and definition test suites
- M1: parse docstrings and directives with the `yard` gem's docstring parser (new runtime dependency, D2)
- M1: add the internal type model and a YARD type expression parser (unions, generics, tuples, hashes, ducks,
  literals and special names; unresolved names stay references)
- M1: add the signature store with inherited docstrings, `(see ...)` references, attribute conventions,
  overloads and the `@!method`/`@!attribute`/`@!parse`/`@!visibility` directives
- M1: show typed signatures on hover for `self`, constant and `Foo.new` receivers, including `@raise`,
  `@deprecated`, `@option`, `@yield` and metadata tags
- M1: add the corpus harness (`rake corpus`, scheduled workflow) and parse fixtures
- M0: add the Indexer Adapter interface and the `RubyIndexer` backend for Ruby LSP 0.26.x
- M0: read per-add-on settings and log through Ruby LSP's client notifications
- M0: forward watched file changes to adapter subscribers for cache invalidation
- M0: record the add-on API availability audit in the requirements document
- Add a fixture project, shared adapter contract tests, and a CI matrix over supported Ruby LSP versions

## [0.1.0] - 2026-09-24

- Initial release
