## [Unreleased]

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
