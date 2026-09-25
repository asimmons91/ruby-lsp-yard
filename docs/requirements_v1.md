# Ruby LSP YARD Add-on — Requirements (V1)

| | |
|---|---|
| **Status** | Accepted |
| **Last updated** | 2026-09-24 |
| **Working name** | `ruby-lsp-yard` (see D12) |
| **Target host** | Ruby LSP 0.26.x stable (`RubyIndexer`) and 0.27 (`Rubydex`, M6); 0.26 drop timing is D1 |

Items marked **⚠ Open decision (Dn)** depend on a choice that has not been made yet. Section 13 lists all of them, each with a proposed default. Items marked **🔍 Verify** depend on a Ruby LSP API detail that must be confirmed against the source of the target version before implementation.

---

## 1. Overview

### 1.1 Problem
Ruby LSP gives accurate navigation and completion for constants, and for methods when it can work out the receiver's type. It does not read type information from YARD documentation. As a result, method completion, hover and signature help are weak in untyped Ruby codebases, even when those codebases carry thorough YARD `@param` and `@return` tags. Solargraph covers this, but as a separate language server that users must run instead of, or alongside, Ruby LSP.

### 1.2 Goal
Ship a Ruby LSP add-on that treats YARD tags as type annotations and uses them to improve:
1. Type-aware method completion (`foo.` → methods of `foo`'s documented type)
2. Hover and signature help that show documented types
3. Go to definition on method calls whose receiver type is known from YARD
4. Help writing YARD comments: tag and type completion, comment skeleton generation
5. Diagnostics for broken or inconsistent YARD documentation

### 1.3 Non-goals
- Being a type checker. Type-mismatch diagnostics are limited and opt-in (M5).
- Replacing Sorbet, Steep or RBS tooling. In projects that use those, the add-on steps back (see D5).
- Generating HTML documentation or replacing `yardoc`.
- Executing project code at runtime to discover methods, as ruby-lsp-rails does.

### 1.4 Success metrics (proposed)
- On a fixture corpus with YARD coverage, completion after `.` returns the correct method set for ≥ 90% of receivers whose types can be derived from YARD tags.
- No noticeable regression in Ruby LSP responsiveness (performance budgets in §4.1).
- Zero server crashes caused by malformed YARD comments across a large real-world corpus (the top 100 gems by downloads).

---

## 2. Background & constraints

| Constraint | Impact |
|---|---|
| **The add-on API is experimental.** It can change between minor versions. | Pin the supported `ruby-lsp` range with `RubyLsp::Addon.depend_on_ruby_lsp!`. If the installed version is outside the range, Ruby LSP skips activating the add-on and shows a warning. Run CI against every supported minor version. |
| **The indexer is changing.** Stable 0.26.x uses `RubyIndexer`. The 0.27.0 betas removed it and replaced it with Rubydex, and upstream is no longer changing the old indexer. | Every lookup against the indexer must go through an adapter layer (§3, M0 and M6). |
| **Completion does not reach add-ons inside comments.** In 0.26.11, completion locates the cursor using a fixed list of node types and returns an empty list when none matches. Prism does not produce nodes for comments. | Tag and type completion inside comments (M4) is provided by a version-guarded monkeypatch of the completion request (D3, decided). |
| **Only one AST pass per request.** Add-on listeners share Ruby LSP's Prism dispatcher. | All features are listeners that respond to node events. The add-on must not re-parse or walk the AST again on the request path. |
| **Ruby LSP already shows comment text on hover** for definitions it can resolve. | The add-on's hover must add structured type information without repeating the raw docstring (D13). |
| **Ruby LSP skips some features in Sorbet-typed files.** | The add-on needs a consistent policy for coexisting with Sorbet and RBS (D5). |
| **Prior art:** Solargraph reads YARD directives, has supported `@!parse` for a long time, and added full `@!macro` support in 0.60.x. | Use Solargraph's behavior as the reference for edge cases and compatibility (D6). |

---

## 3. Architecture

```
            ┌────────────────────── Ruby LSP server process ───────────────────────┐
            │                                                                      │
 editor ◄──►│  Ruby LSP requests ──► Prism dispatcher ──► Add-on feature listeners │
            │                                              │                       │
            │                                              ▼                       │
            │                                   ┌── Inference Engine ──┐          │
            │                                   │                      │          │
            │                         Signature Store          Core/Stdlib Types  │
            │                          ▲        ▲               (RBS bridge, M3)  │
            │                          │        │                                  │
            │               Tag Extractor   Type Expression Parser                │
            │                          ▲                                           │
            │                          │                                           │
            │                   Indexer Adapter ──► RubyIndexer (0.26) │ Rubydex (0.27)
            │                          │                                           │
            │                   Disk cache (gem signatures)                        │
            └──────────────────────────────────────────────────────────────────────┘
```

| Component | Responsibility |
|---|---|
| **Indexer Adapter** | The only code that talks to the host indexer. Finds method, attribute and constant definitions; returns their comments and locations; resolves constant names relative to a nesting; returns a class's ancestors; notifies the add-on when files change. |
| **Tag Extractor** | Turns comment text into structured tags and directives, attached to their owning definition. Must never raise on malformed input. |
| **Type Expression Parser** | Turns YARD type strings into the add-on's internal type model (§3.1). |
| **Signature Store** | Maps each method (owner, name, singleton or instance) to its parameter types, return type, block types, overloads and visibility. Also holds attribute types. Filled lazily and memoized. |
| **Inference Engine** | Works out the type of an expression at a given position (§M2). |
| **Core/Stdlib Types** | Adapts RBS core and stdlib signatures into the same type model (M3). |
| **Feature listeners** | Completion, hover, signature help, definition and (optionally) inlay hints. Each writes to Ruby LSP's response builders. |
| **Disk cache** | Stores parsed signatures for dependency gems, keyed by gem name, gem version and add-on schema version. |

### 3.1 Internal type model
The model must be able to represent at least:
- `Instance(Class, type_args[])`: `String`, `Array<Foo>`
- `Singleton(Class)`: the class object itself, as in `Class<Foo>` or a constant reference
- `Union(types[])`: `String, nil`
- `Tuple(types[])`: `Array(String, Integer)`
- `HashOf(key, value)`: `Hash{Symbol => Integer}`
- `Duck(method_names[])`: `#to_s`, `#read, #close`
- Specials: `nil`, `Boolean` (= `true | false`), `self`, `void`, `undefined`/`untyped`
- `Literal(value)`: `:foo`, `"bar"`, `1`. Parsed but treated as the literal's class for completion (stretch goal).
- `Unknown`: the result of failed inference. Never shown to users as a type.

---

## 4. Cross-cutting requirements

### 4.1 Performance (proposed budgets, measured on a warm cache on a mid-range laptop)
- **NFR-P1:** Add-on activation must not block the server from handling requests. Any warm-up work runs in a background thread and must be cancellable on `deactivate`.
- **NFR-P2:** Added latency per request at p95: completion ≤ 50 ms, hover ≤ 30 ms, signature help ≤ 30 ms, definition ≤ 30 ms.
- **NFR-P3:** Inference must stop at a fixed budget (proposed: 20 ms, or a depth of 8 chained calls) and return `Unknown` rather than keep blocking.
- **NFR-P4:** Additional resident memory ≤ 25% of Ruby LSP's baseline on a 5k-file project with dependencies.
- **NFR-P5:** Docstrings are parsed on demand and memoized. Nothing parses the whole workspace's YARD comments up front on the request path.

### 4.2 Robustness
- **NFR-R1:** Malformed tags, unparseable type expressions and invalid directives never raise out of the add-on. They degrade to `Unknown` and, in M5, produce a diagnostic.
- **NFR-R2:** Every listener entry point is wrapped so that an exception in the add-on cannot break Ruby LSP's own response for the same request. Exceptions are logged.
- **NFR-R3:** Recursive types, recursive `@return [self]` chains and cyclic macro expansion are all detected and cut off.

### 4.3 Compatibility
- **NFR-C1:** Declare the supported `ruby-lsp` range. It starts at `~> 0.26.0` and widens once M6 is done (D1).
- **NFR-C2:** Minimum Ruby version: D11.
- **NFR-C3:** Works in every editor that Ruby LSP supports. Features that depend on a client capability, such as snippets, must fall back gracefully when the client doesn't support it.
- **NFR-C4:** Produces no duplicate results when used alongside ruby-lsp-rails and other common add-ons.

### 4.4 Configuration
- **NFR-CFG1:** Settings are read from Ruby LSP's per-add-on settings (`addonSettings` keyed by the add-on's name). 🔍 Verify the API in the target version.
- **NFR-CFG2:** Every major feature can be switched off independently: completion, hover, signature help, definition, inlay hints, diagnostics, authoring help.
- **NFR-CFG3:** Defaults work with no configuration at all.

### 4.5 Observability
- **NFR-O1:** Log through Ruby LSP's logging mechanism (not `$stdout`, which would corrupt the LSP stream).
- **NFR-O2:** A debug setting logs how inference reached each result (which tag produced each type), to make bug reports possible.

### 4.6 Testing
- **NFR-T1:** Unit tests for the Tag Extractor, Type Parser and Inference Engine run without starting the server.
- **NFR-T2:** Integration tests use Ruby LSP's test helpers (🔍 verify `RubyLsp::TestHelper` in the target version) to run real LSP requests against fixture projects.
- **NFR-T3:** A corpus test parses the YARD comments of the top 100 gems. It must finish without errors and report how many type expressions failed to parse.
- **NFR-T4:** Performance benchmarks run in CI against the budgets in §4.1 and fail the build on a regression of more than 20%.
- **NFR-T5:** The CI matrix covers every supported Ruby LSP minor version and every supported Ruby version.

---

## 5. Milestone M0 — Foundation & indexer adapter

**Goal:** A gem that Ruby LSP activates, with an indexer adapter and a confirmed list of which features the add-on API allows.

### Functional requirements
- **FR-M0-01:** Gem skeleton with `lib/ruby_lsp/<name>/addon.rb`, so Ruby LSP discovers it. Implements `activate`, `deactivate`, `name` and `version`.
- **FR-M0-02:** Declares the supported version range with `depend_on_ruby_lsp!`.
- **FR-M0-03:** Defines the Indexer Adapter interface with at least these operations:
  - `method_definitions(owner, name, singleton:)` → locations and comments
  - `attribute_definitions(owner, name)`
  - `resolve_constant(name, nesting)` → fully qualified name or nil
  - `ancestors(fully_qualified_name)` → linearized ancestor list, including modules
  - `methods_of(owner, prefix:)` → candidate methods for completion
  - `on_change(uris)` → invalidation callback
- **FR-M0-04:** Implements the adapter for `RubyIndexer` (0.26.x).
- **FR-M0-05:** **API availability check.** Record which feature hooks add-ons can use in the target versions: completion, completion resolve, hover, signature help, definition, inlay hints, code actions, code lens, diagnostics/linter registration, on-type formatting. Every gap becomes either an upstream request or a descoped feature. The result is a table added to this document.
- **FR-M0-06:** Adds the settings plumbing (§4.4) and logging (§4.5).
- **FR-M0-07:** Sets up the fixture projects, test harness and CI matrix (§4.6).

### Acceptance criteria
- The add-on activates in VS Code and Neovim with Ruby LSP 0.26.x and shows up in Ruby LSP's list of add-ons.
- The adapter contract tests pass against `RubyIndexer`.
- The API availability table is complete, and every gap has an owner.

### 5.1 Add-on API availability (FR-M0-05 audit)

Audited against `ruby-lsp` v0.26.0 and v0.26.11. The add-on hook set is identical across the whole 0.26 minor.
Evidence is the method that invokes the hook in `lib/ruby_lsp/`, or the request that serves the feature without
consulting add-ons.

| Feature | 0.26.x | Mechanism / evidence | Disposition / owner |
|---|---|---|---|
| Completion | ✅ | `Addon#create_completion_listener`, invoked by `Requests::Completion` | M2 (FR-M2-14) |
| Completion resolve | ❌ | No add-on hook; `completionItem/resolve` only runs `Requests::CompletionResolve` for Ruby LSP's own items | Descope: emit documentation eagerly in M2 (FR-M2-14). Upstream owner: ruby-lsp completion-resolve hook |
| Hover | ✅ | `Addon#create_hover_listener`, invoked by `Requests::Hover` | M1 (FR-M1-12) |
| Signature help | ❌ | No add-on hook; `Requests::SignatureHelp` ignores add-ons | Upstream owner: ruby-lsp signature-help hook; FR-M1-13 falls back to an upstream request if none is added |
| Definition | ✅ | `Addon#create_definition_listener`, invoked by `Requests::Definition` | M2 (FR-M2-19) |
| Inlay hints | ❌ | No add-on hook; `Requests::InlayHints` ignores add-ons | Descoped (D14 default); revisit if a hook appears |
| Code actions | ❌ | No add-on hook; `Requests::CodeActions` ignores add-ons | Upstream owner: ruby-lsp code-action hook (FR-M4-06 skeleton, FR-M5-03 quick fixes) |
| Code lens | ✅ | `Addon#create_code_lens_listener`, invoked by `Requests::CodeLens` | M4 fallback for comment skeleton generation (FR-M4-06) |
| Diagnostics / linter registration | ⚠️ | `GlobalState#register_formatter(identifier, instance)` supports `run_diagnostic`, but the linter only activates when the user lists the identifier in `rubyLsp.linters`; add-on linters are not auto-detected | M5 (FR-M5-01) implemented: the add-on registers `"yard"` and the README documents the `rubyLsp.linters` requirement. Upstream owner for auto-detection |
| On-type formatting | ❌ | No add-on hook | Descope: not needed by V1 |
| Settings | ✅ | `GlobalState#settings_for_addon(name)` reads `addonSettings` keyed by the add-on's name | M0 (FR-M0-06) |
| File watching | ✅ | `Addon#workspace_did_change_watched_files(changes)`; the server registers `**/*.rb` watchers for add-ons that respond to it | M0 (`Indexer::Adapter#on_change`) |

Bonus hooks available in 0.26.x and unused by V1: document symbols, semantic highlighting, discover tests and formatter
registration. Every gap above has a disposition; upstream rows become issues against
[Shopify/ruby-lsp](https://github.com/Shopify/ruby-lsp) when the owning milestone starts.

Re-audited against `ruby-lsp` v0.27.0.beta5 in M6 (§11.1): the hook set is unchanged; only `NodeContext`'s
surrounding-method shape and singleton nesting markers moved, and both are normalized by `HostContext`.

---

## 6. Milestone M1 — YARD parsing, signature store, hover & signature help

**Goal:** Read YARD tags into a signature store, and show their types wherever Ruby LSP can *already* work out the receiver: `self`, constants, `Foo.new`, and the other cases its current type inferrer handles.

### 6.1 Tag extraction
- **FR-M1-01:** Parse docstrings with the parser chosen in D2.
- **FR-M1-02:** Tags supported in M1:

| Tag | Used for |
|---|---|
| `@param name [Types] desc` | Parameter types |
| `@return [Types] desc` | Return type |
| `@yield [params] desc` | Block description |
| `@yieldparam name [Types]` | Block parameter types |
| `@yieldreturn [Types]` | Block return type |
| `@option hash_name [Types] :key (default) desc` | Types of an options hash's keys (shown on hover) |
| `@raise [Types]` | Shown on hover |
| `@deprecated` | Shown on hover and completion (strikethrough tag) |
| `@overload signature` | Multiple signatures, each with its own nested tags |
| `@api`, `@note`, `@see`, `@since`, `@example` | Shown on hover only |

- **FR-M1-03:** Directives supported in M1: `@!method`, `@!attribute [r|w|rw] name`, `@!parse [ruby]` and `@!visibility`. Each creates entries in the signature store. `@!parse` text is parsed with Prism and indexed within the class or module where the comment appears.
- **FR-M1-04:** Attribute conventions:
  - `# @return [Type]` directly above `attr_reader`, `attr_writer` or `attr_accessor` gives the attribute's type.
  - An `attr_*` call with several names applies the type to all of them.
- **FR-M1-05:** `@param` tags that don't match a parameter are kept (so M5 can report them) but ignored for typing.
- **FR-M1-06:** Keyword, optional, splat (`*args`), double-splat (`**opts`) and block (`&blk`) parameters are matched by name, with or without the sigil in the tag.

### 6.2 Type expression parser
- **FR-M1-07:** Parses the full YARD types grammar: comma unions, `<>` generics, `()` tuples, `{K => V}` hashes, `#method` duck types, nesting, and whitespace tolerance.
- **FR-M1-08:** Resolves class names relative to the lexical nesting of the documented definition, using `resolve_constant`. Names that don't resolve stay as unresolved references; they are not errors at this stage.
- **FR-M1-09:** Maps special names: `Boolean`, `nil`, `true`, `false`, `self`, `void`, `undefined`, `Object` (treated as unknown for completion; D7), `Class<T>` → `Singleton(T)`.

### 6.3 Signature store
- **FR-M1-10:** Looks up a method signature by owner, name and whether it's a singleton method. For a method without its own docs, it walks the ancestors to find an inherited docstring. That follows YARD's `(see Foo#bar)` convention and plain inheritance.
- **FR-M1-11:** Entries for a file are invalidated when the file changes or is saved.

### 6.4 Features
- **FR-M1-12: Hover.** On a method call or definition with YARD types, show a formatted signature, e.g. `def fetch(key: Symbol, default: String?) → String`. Show `@raise`, `@deprecated` and `@overload` variants too. Don't repeat the prose docstring that Ruby LSP already shows (D13).
- **FR-M1-13: Signature help.** While typing arguments, show parameter types and descriptions and highlight the active parameter. Each `@overload` is shown as a separate signature. 🔍 This depends on FR-M0-05: if add-ons can't provide signature help, move it to an upstream request.
- **FR-M1-14:** Hover over a type name inside a YARD comment shows that class's documentation. This is best-effort, because hover has the same comment-node limitation as completion (D3).

### Acceptance criteria
- On fixtures, every supported tag and directive round-trips into the signature store.
- The corpus test (NFR-T3) parses ≥ 99% of type expressions in the top 100 gems.
- Hover and signature help show types for calls on `self`, on constants and on `Foo.new` receivers.

### 6.5 M1 implementation notes (2026-09-24)
- **FR-M1-13 (signature help)** is blocked by the API gap recorded in §5.1: Ruby LSP 0.26's
  `Requests::SignatureHelp` ignores add-ons. It is descoped from M1 and tracked as an upstream request;
  `enableSignatureHelp` is reserved.
- **FR-M1-14** ships with the M4 comment patch (FR-M4-P6). M1 hover covers method calls only.
- 0.26's hover targets (`Listeners::Hover::ALLOWED_TARGETS`) exclude `def` nodes, so the FR-M1-12 mention of
  hover on a method *definition* is unreachable for add-ons; only calls and the other allowed nodes can be
  served.
- M1 reuses Ruby LSP's `TypeInferrer` for receiver types; the M2 inference engine replaces it behind the same
  wrapper.
- Every `@overload` is rendered as its own signature on M1 hover until signature help is available.
- Directive discovery is limited to comments attached to an indexed entry (class, module, constant, method or
  attribute); standalone directive comments attached to nothing are not visible to the indexer.
- NFR-T3 runs as the opt-in `rake corpus` task and the scheduled `YARD corpus` workflow, which installs the
  snapshot in `test/corpus/gems.txt`. The default suite keeps a small committed corpus with a zero-failure
  assertion.

---

## 7. Milestone M2 — Type inference & method completion

**Goal:** Infer receiver types from YARD tags and code, and use them for completion after `.`, hover and go to definition on arbitrary expressions.

### 7.1 Inference
- **FR-M2-01:** Literals: String, Symbol, Integer, Float, Rational, Complex, Array, Hash, Range, Regexp, `nil`, `true`, `false`, heredocs and string interpolation.
- **FR-M2-02:** Constants → `Singleton(C)`. `C.new` → `Instance(C)`, unless `C.new` has its own `@return` tag.
- **FR-M2-03:** `self`: an instance of the enclosing class in instance methods, the singleton in class methods, and the right type inside `class << self`.
- **FR-M2-04:** Method parameters have their `@param` types everywhere in the method body. Parameters without docs are `Unknown`.
- **FR-M2-05:** Local variables: the type is the union of the types of all assignments to that variable that come before the cursor in the same scope. This first version doesn't follow control flow (D8).
- **FR-M2-06:** Call chains: the type of `recv.m(...)` is `m`'s `@return` type, looked up on `recv`'s inferred type. `@return [self]` returns the receiver's type.
- **FR-M2-07:** Block parameters: when a call's method has `@yieldparam` tags, the block's parameters get those types.
- **FR-M2-08:** Instance variables: typed from `@!attribute` or attribute docs with the same name, or else from assignments of typed values anywhere in the class (union). The union is scoped to the class and doesn't cross files unless the class is reopened.
- **FR-M2-09:** Union receivers: completion shows methods that exist on any member of the union. Items that exist only on some members are labeled with the member type. `nil` is left out of completion (D7).
- **FR-M2-10:** Duck types: completion offers only the listed methods.
- **FR-M2-11:** Inherited and mixed-in methods come from the adapter's `ancestors`. Singleton-side lookups include `extend`ed modules.
- **FR-M2-12:** The type budget (NFR-P3) is enforced. Recursion is cut off with a visited set of (method, argument types).
- **FR-M2-13:** Solargraph-style inline local annotations (`# @type [Foo]` above an assignment) are supported if D6 says so.

### 7.2 Completion
- **FR-M2-14:** After `recv.`, suggest the methods of `recv`'s inferred type. Each item includes:
  - kind `Method`
  - `labelDetails.detail`: parameter list with types
  - `labelDetails.description`: return type
  - documentation: the docstring summary, loaded through completion resolve if add-ons can use it (🔍 FR-M0-05)
- **FR-M2-15:** Method visibility is respected: `private` methods are offered only when the receiver is implicit `self`, and `protected` only within the same class family.
- **FR-M2-16:** Items are ranked: the receiver's own class first, then ancestors in order, then `Object` and `Kernel` last.
- **FR-M2-17:** No duplicates with Ruby LSP's own completion items. If an identical method appears in both, the add-on doesn't emit it. 🔍 This depends on whether the add-on can see what the other listeners have already added to the response builder. If it can't, the add-on only emits for receivers that Ruby LSP can't resolve itself.
- **FR-M2-18:** Behavior when the receiver type is `Unknown` is set by D7.

### 7.3 Go to definition
- **FR-M2-19:** For `recv.m` with a known receiver type, jump to the definitions of `m` on that type and its ancestors. Where the API allows, narrow Ruby LSP's fallback of listing every method with that name (🔍 FR-M0-05).

### 7.4 Inlay hints (optional, D14)
- **FR-M2-20:** Show inferred types after local variable assignments and in block parameters. Off by default.

### Acceptance criteria
- ≥ 90% correct completion on the M2 fixture corpus (§1.4).
- All performance budgets in §4.1 are met on the benchmark project.
- No duplicate completion items when used with plain Ruby LSP and with ruby-lsp-rails.

### 7.5 M2 implementation notes (2026-09-24)
- **FR-M2-20 (inlay hints)** is descoped in 0.26 for the same reason as FR-M1-13: `Requests::InlayHints` ignores
  add-ons (§5.1). `enableInlayHints` stays reserved.
- **Completion resolve** has no add-on hook, so completion documentation (the docstring summary) is emitted
  eagerly. Methods without YARD types are left to Ruby LSP's own listener so no item is duplicated (FR-M2-17).
- **Enriched items replace host items.** Ruby LSP passes one `CollectionResponseBuilder` to its own completion
  and definition listeners and to the add-on's, whose `#response` exposes the mutable item array. The add-on
  prunes host items for labels it can enrich and, for definition, replaces the fallback list when it resolved the
  receiver itself (FR-M2-19). The capability is probed per request; if the array is unavailable the add-on falls
  back to emitting only labels the host did not add. M6 must re-check this probe.
- **Scope access.** `NodeContext` exposes only the target node and `dispatch_once` visits nothing else, so
  local/ivar/block inference reads the document AST through the private `@nesting_nodes` array (FR-M2-05/07/08).
  The accessor is version-guarded and degrades to `Unknown` when the shape changes; only the enclosing scope
  subtree is walked, once per request and memoized. Nothing is re-parsed.
- **Inline `@type` (FR-M2-13, D6)** is deferred to M7: comments are not part of the AST, and reading them from
  disk would be stale for unsaved buffers.
- **Sorbet policy (D5).** The completion and definition hooks do not receive the file's `SorbetLevel`, so the
  per-file "turn off in Sorbet-typed files" rule cannot be applied in M2. Features defer wherever Ruby LSP itself
  defers.
- **Inference details.** `@return [self]` is substituted with the receiver's type; `Foo.new` uses a documented
  `self.new` return type unless it comes from `Class`/`Object`; the budget is 20 ms/8 chained calls plus a visited
  set of `(method, receiver type)`; `nil` is dropped from unions and `Object` is unknown (D7).
- **Corpus and budgets.** `test/corpus/test_completion_corpus.rb` enforces the ≥ 90% acceptance criterion and
  forbids known-wrong labels. `rake benchmark` measures warm-cache inference and completion enrichment against
  the §4.1 budgets; the CI regression gate (NFR-T4) is deferred.

---

## 8. Milestone M3 — Core/stdlib types, generics & gem caching

**Goal:** Chains through core classes resolve correctly (`users.first.name`), and YARD comments in dependencies are read efficiently.

### Functional requirements
- **FR-M3-01:** Load RBS signatures for core and stdlib (the `rbs` gem is already a dependency of Ruby LSP) and convert them into the internal type model. This covers overloads, generics, block signatures, optional and keyword parameters, and interface types (mapped to `Duck`).
- **FR-M3-02:** Generics: YARD `Array<Foo>` becomes `Instance(Array, [Foo])`. Method return types substitute type parameters, e.g. `Array[T]#first` → `T`, `Hash[K,V]#each` → yields `[K, V]`.
- **FR-M3-03:** Block return inference: the type of a block is the type of its last expression. It's used to resolve types like `Array#map` → `Array<U>`. This is a stretch goal and has to fit within the inference budget.
- **FR-M3-04:** When a method has both YARD docs and RBS signatures, which one wins is set by D5.
- **FR-M3-05:** Dependency gems: parse YARD comments in bundled gems lazily, the first time a method in them is looked up. Persist the results to a disk cache (location: D9) keyed by gem name, gem version and the add-on's schema version. Invalidate automatically when `Gemfile.lock` changes.
- **FR-M3-06:** Which gems are included is set by D9. Gems excluded in Ruby LSP's own indexing configuration are always excluded.
- **FR-M3-07:** Optionally load gem RBS from an `rbs collection` if the project has one (D5).

### Acceptance criteria
- On fixtures, correctly infers `[1, 2].first` → `Integer`, `hash.each { |k, v| }` → `k` and `v` typed, and `str.split(",").map(&:strip)` → `Array<String>` (stretch goal).
- A cold start with 200 gems doesn't block requests. A warm start loads the gem cache in under 2 s in the background.

### 8.1 M3 implementation notes (2026-09-24)
- **RBS environment (FR-M3-01).** `RubyLsp::Yard::Rbs::Loader` builds an `RBS::Environment` for core plus every
  stdlib library shipped by the `rbs` gem (~940 classes, ~120 ms measured) in a background thread at activation
  (NFR-P1) and is cancellable on `deactivate`. `Rbs::Converter` maps RBS types to the internal model:
  interfaces become `Duck`s, aliases expand with a depth cap, intersections are approximated as unions, records
  become `HashOf`s with literal keys, and `untyped`/`any` map to `UNTYPED`.
- **RBS wins over YARD (FR-M3-04, D5).** `SignatureStore` asks the RBS source first for the requested owner and,
  in the ancestor walk, before each ancestor's YARD definitions. Owners absent from the RBS environment
  (workspace classes) keep their YARD definitions, so documented `self.new` overrides still work.
- **Generics (FR-M3-02).** `Types::TypeVar` and `Types.substitute_type_vars` were added; `Resolution::Member`
  carries the receiver's type arguments; `Signature#type_params`/`#method_type_params` are populated by the RBS
  source and bound at the call site by the engine and by completion/hover label rendering. `Hash#each`'s single
  tuple yield destructures into `|k, v|`.
- **Block returns (FR-M3-03).** `Array#map`'s method type variable binds to the block's last expression, and
  `&:sym` blocks look the method up on the element type. Block parameter bindings are threaded through
  inference and the pass runs inside the existing 20 ms/8-call budget.
- **Gem caching (FR-M3-05/06, D9).** `Gems::Locator` maps definition paths to bundled gems; `Gems::Cache`
  stores built signatures per gem and version under `~/.cache/ruby-lsp-yard/<schema>/` with atomic writes and a
  `Gemfile.lock` digest embedded in each payload, so a changed lock invalidates it. Gems excluded from Ruby
  LSP's own indexing never reach the store, satisfying FR-M3-06 by construction. The cache is read per gem on
  first use instead of being warmed up front, so a cold start never blocks and a warm start loads only the gems
  it touches in microseconds. `Locator` ignores `.rbs` paths, which carry no YARD comments. Writes are batched
  (first signature per gem immediately, then at most every 32 writes or 2 s, plus on `deactivate`) so enriching
  a completion does not rewrite the payload per method.
- **Readiness invalidation.** Signatures resolved while the RBS environment was still loading would otherwise be
  memoized against their YARD/host fallback for the session. `Loader#subscribe`/`Source#subscribe` notify the
  signature store when the environment is published and the store drops its caches, so `RBS wins` applies even
  to core methods looked up during the load window.
- **FR-M3-07** (`rbs collection`) is deferred to M7 with the rest of the D5 ecosystem work. RBS intersections
  and records are approximated, and core go-to-definition still points at the `rbs` gem's `.rbs` files because
  the host index supplies those locations.
- **Hover** substitutes the receiver's generic arguments through `Engine#signature_for`, so core methods render
  `def first() → Integer` rather than `→ E`.
- **Testing and benchmarks.** `test/corpus/test_m3_corpus.rb` asserts the acceptance cases; `benchmark/rbs.rb`
  measures environment build and lookup latency, and `benchmark/inference.rb` adds generic core and block-return
  cases.
- **Cache trust model.** `Marshal.load` has no class allowlist on Ruby 3.4/4.0 (`permitted_classes:` is not a
  supported keyword), so the payload is treated as trusted user-local state: written atomically by the add-on,
  read only from the user's own cache directory, with the payload version and `Gemfile.lock` digest validated
  before any signature is returned. A tampered cache file is equivalent to tampering with any other file in the
  user's home directory.

---

## 9. Milestone M4 — YARD authoring support

**Goal:** Help people write YARD comments. Completion inside comments works through a monkeypatch (D3, decided).

### Reaching comments: the monkeypatch
- **FR-M4-P1:** Prepend a module to `RubyLsp::Requests::Completion`. When the cursor is inside a comment (checked against the document's Prism comment list), it returns the add-on's comment completions. Otherwise it passes the request through to Ruby LSP unchanged.
- **FR-M4-P2:** The patch is applied only when the running Ruby LSP version is in an explicit list of versions it has been tested with. For any other version it isn't applied, M4 features are switched off, and a warning is logged once. The rest of the add-on keeps working.
- **FR-M4-P3:** The patch does not change behavior outside comments. A test for each supported version confirms that Ruby LSP's own completion results are unchanged in code.
- **FR-M4-P4:** Any exception inside the patch falls back to the original behavior (NFR-R2).
- **FR-M4-P5:** All patch code lives in one file with the exact upstream method it replaces noted, so each Ruby LSP upgrade can be reviewed quickly. Supporting 0.27 (M6) includes re-checking the patch against the rewritten request.
- **FR-M4-P6:** Hover and go to definition on type names inside comments (FR-M1-14) use the same patching approach and follow the same rules (P2 to P5).

### Functional requirements
- **FR-M4-01: Detecting the context.** Tell whether the cursor is in a YARD comment block that belongs to a definition (the comment ends on the line before a `def`, `class`, `module`, `attr_*`, constant assignment or DSL call). Then classify what's being typed:
  - a tag name (`# @re|`)
  - a directive (`# @!|`)
  - a type (`# @param x [Str|`)
  - a parameter name (`# @param |`)
  - free text: no completion
- **FR-M4-02: Tag completion.** Snippet items that replace the whole typed token through `textEdit` (so the typed `@` isn't duplicated). For example, `@ret` → `@return [$1] $0`, with `filterText` `@return`. When the client doesn't support snippets, insert plain text instead.
- **FR-M4-03: Suggestions based on the method below:**
  - one `@param name [$1] $0` item for each parameter that isn't documented yet
  - `@yield`, `@yieldparam` and `@yieldreturn` only if the method contains `yield` or takes a `&block`
  - `@return` hidden or ranked lower if one already exists
  - `@raise` suggested when the body contains `raise SomeError`, pre-filled with that class
- **FR-M4-04: Directive completion:** `@!method`, `@!attribute [r]`, `@!parse`, `@!visibility`, `@!macro` (after M7) and `@!domain` (after M7).
- **FR-M4-05: Type completion inside `[...]`:** constants from the index, filtered by prefix and resolved relative to the definition's nesting. Also YARD's special names, plus snippets for generic shapes (`Array<$1>`, `Hash{$1 => $2}`, `Array($1, $2)`).
- **FR-M4-06: Comment skeleton generation.** A code action (or a code lens, depending on FR-M0-05) on a `def` without docs inserts a full comment: a summary line, one `@param` per parameter, `@yield*` if the method yields, and `@return`. Types are pre-filled when inference knows them.
- **FR-M4-07:** Document the triggering limits:
  - `[` is not a trigger character.
  - VS Code turns off as-you-type suggestions in comments by default (`editor.quickSuggestions.comments`).

  An add-on can't add trigger characters, so type completion needs Ctrl+Space or the `quickSuggestions` setting turned on. Document this in the README.

### Acceptance criteria
- Typing `# @ret` then Tab produces `# @return [|]` in VS Code and Neovim (with nvim-cmp or blink).
- Parameters that are already documented are not suggested again.

### 9.1 M4 implementation notes (2026-09-24)
- **Patch layout (FR-M4-P5).** All prepended modules live in `lib/ruby_lsp_yard/authoring/patch.rb` with the exact
  upstream method each one wraps noted in the header: `Requests::Completion#initialize/#perform`,
  `Requests::Hover#initialize/#perform`, `Requests::Definition#initialize/#perform`,
  `Requests::CodeActions#perform` and `ClientCapabilities#apply_client_capabilities`.
- **Version allowlist (FR-M4-P2).** `Patch::TESTED_VERSIONS` is exactly `%w[0.26.11]`. A unit test asserts the
  installed `RubyLsp::VERSION` is listed, so bumping the `ruby-lsp` dependency fails CI until the patch is
  re-checked and the list updated. Untested versions keep the rest of the add-on working and log one warning.
- **FR-M4-06 uses the code-action patch.** 0.26 offers neither an add-on code-action hook nor a server-side
  `workspace/executeCommand`, so the code-lens fallback in §5.1 cannot execute anything. `Requests::CodeActions`
  is patched to append an eager `WorkspaceEdit` action for an undocumented `def` in the requested range. The
  skeleton draws types from the signature store (inherited/overridden docs) and falls back to placeholders.
- **Snippet support (NFR-C3).** 0.26's `ClientCapabilities` keeps only the flags it uses, so
  `apply_client_capabilities` is prepended to record `completionItem.snippetSupport`. The `initialize` request
  applies capabilities before add-ons load, so in practice the flag is unknown at activation; the add-on then
  assumes snippet support and the new `enableSnippets` setting (default on) opts out for clients without it.
  When the capability is observed as false, plain text is inserted; `enableAuthoring` off leaves the host
  response untouched.
- **Comment detection (FR-M4-01).** A version-guarded probe of `RubyDocument`'s Prism parse result exposes the
  comment list. The context finds the cursor's comment, assembles the contiguous block, finds the definition on
  the following line (skipping `private`/`protected` modifiers) and classifies the token as tag, directive, type,
  parameter name or free text. Any failure returns nil and the request falls through to Ruby LSP (NFR-R1/R2).
- **Type completion (FR-M4-05).** The adapter gained `constant_candidates(prefix, nesting)`, wrapping
  `RubyIndexer#constant_completion_candidates`; results are rendered as the shortest name that resolves from the
  definition's nesting. YARD specials and `Array<T>`/`Hash{K => V}`/`Tuple(a, b)`/`Class<T>` snippets sit
  alongside the index candidates.
- **Comment hover and definition (FR-M4-P6, FR-M1-14).** Hover shows the class or module declaration and its
  docstring; definition returns `LocationLink`s to the class. Both pass through unless `enableAuthoring` and the
  corresponding `enableHover`/`enableDefinition` setting are on.
- **FR-M4-07.** The README documents that `[` is not a trigger character and that VS Code needs
  `editor.quickSuggestions.comments` (or Ctrl+Space) for suggestions inside comments.
- **Testing.** Unit suites cover context detection, tag/type/param completion, type lookup, skeletons, the
  version allowlist and patch idempotency; LSP integration tests run the patched requests through Ruby LSP's test
  server, including a pass-through test that compares code completion with authoring on and off (FR-M4-P3) and
  an exception-fallback test (FR-M4-P4).

---

## 10. Milestone M5 — YARD diagnostics

**Goal:** Report YARD documentation that is broken or doesn't match the code. Reported through Ruby LSP's linter registration (🔍 verify registering a formatter or linter with `run_diagnostic` and the `rubyLsp.linters` setting).

| Rule | Default | Description |
|---|---|---|
| `YARD/UnknownParam` | warning | A `@param` names a parameter the method doesn't have |
| `YARD/UnresolvedType` | warning | A type name doesn't resolve to a known constant |
| `YARD/InvalidTypeSyntax` | error | A type expression can't be parsed |
| `YARD/DuplicateTag` | warning | A `@param` or `@return` appears twice (outside an `@overload`) |
| `YARD/InvalidDirective` | error | A directive is malformed, or its `@!parse` text has a Ruby syntax error |
| `YARD/YieldWithoutBlock` | info | `@yield*` on a method that neither yields nor takes a block |
| `YARD/MissingParam` | off | A parameter has no `@param` tag |
| `YARD/MissingReturn` | off | A public method has no `@return` |
| `YARD/ArgumentTypeMismatch` | off | A literal argument's type conflicts with the `@param` type (light type checking) |
| `YARD/ReturnTypeMismatch` | off | A literal return value conflicts with `@return` |

- **FR-M5-01:** Each rule's severity can be configured, and each rule can be turned off (D10).
- **FR-M5-02:** Inline suppression with `# yard:disable RuleName` (the syntax is still open, D10).
- **FR-M5-03:** Quick fixes where the API allows: rename a `@param` to the closest matching parameter, add the missing `@param` tags, fix the spelling of a type name.
- **FR-M5-04:** Diagnostics run on save and on open. On change only if it stays within the budget.

### 10.1 M5 implementation notes (2026-09-24)

- **Registration (FR-M5-01).** The add-on registers `Diagnostics::Linter` under the identifier `"yard"` with
  `GlobalState#register_formatter` during `activate`, and only when `enableDiagnostics` is on. Ruby LSP 0.26's
  `Requests::Diagnostics` resolves `active_linters` from `initializationOptions[:linters]`, so the identifier must
  be listed by the user (`"rubyLsp.linters": ["yard"]`) and is documented in the README. Auto-detection remains an
  upstream request (§5.1).
- **Scanning (FR-M5-01..04).** `Diagnostics::Scanner` walks the live document AST once (not the index) and pairs
  methods, `attr_*` calls, namespaces and constants with the contiguous comment block immediately above them,
  tracking class nesting, `class << self`, `private`/`protected`/`public`/`module_function`,
  `private :name`/`private def` forms and class-level DSL blocks. Only comment blocks containing `@` are parsed, so
  prose-only comments cost nothing (NFR-P5).
- **Rules.** `YARD/InvalidTypeSyntax`, `YARD/UnresolvedType`, `YARD/UnknownParam`, `YARD/DuplicateTag`,
  `YARD/InvalidDirective` and `YARD/YieldWithoutBlock` run by default. Unknown and malformed directives are found
  by scanning the comment text, because YARD silently drops them; every YARD directive (`group`, `endgroup`,
  `scope`, ...) is recognized, along with Solargraph's `domain` for M7. `YARD/UnresolvedType` skips single-capital
  type variables (`Array<T>`) and underscore-prefixed RBS interface names, and `YARD/UnknownParam` accepts the
  names inside destructured parameters (`def m((a, b))`). `YARD/MissingParam`, `YARD/MissingReturn`,
  `YARD/ReturnTypeMismatch` and `YARD/ArgumentTypeMismatch` default to off; all four only consider methods that
  already carry some YARD documentation.
- **Light type checking (D10).** The two mismatch rules compare literal nodes against signatures built from YARD
  tags only: `Signature#source` was added (`:yard`/`:rbs`; the gem cache schema version was bumped so old payloads
  are ignored) and RBS-sourced signatures are skipped, which avoids false positives from RBS generics and
  overloads. `*rest` arguments are compared against the container's element type (a bare `Array` carries no
  element information and is skipped), and keywords that fall into `**options` are checked against the matching
  `@option` tag when there is one. `nil` return literals are ignored, and union, duck, `self`, `void` and type
  variables never conflict. `YARD/ArgumentTypeMismatch` resolves call receivers through the inference engine, so
  it is a document-wide rule; `YARD/ReturnTypeMismatch` walks explicit `return` literals of each documented
  method.
- **Suppression and severities (FR-M5-01/02, D10).** Severities come from the `diagnosticRules` map in the
  add-on settings (`false`, `"off"` and `"none"` disable a rule; invalid values fall back to the default).
  `# yard:disable Rule[, Rule...]` anywhere in a definition's comment block suppresses those rules for that
  definition; a bare `# yard:disable` suppresses every rule for it. There is no file-level form.
- **Budgets and caching (FR-M5-04).** The linter runs cheap rules first behind a 100 ms deadline; once exhausted,
  the remaining (expensive) rules are skipped and the findings so far are returned. Ruby LSP caches the
  diagnostic response per document version and clears it on edits, so open, save and change pulls cannot serve a
  stale report.
- **Quick fixes (FR-M5-03).** Ruby LSP 0.26 still has no add-on code-action hook, so the M4 version-guarded
  `Requests::CodeActions` patch was extended under the same rules (FR-M4-P2..P5): it recomputes the fixable
  diagnostics for the document and appends quick fixes intersecting the requested range. It can rename an
  unknown `@param` to the closest parameter, add a missing `@param` (types prefilled from inherited
  documentation when available), and replace an unresolved type name with the closest indexed constant. Quick
  fixes require `enableDiagnostics` and `enableAuthoring`.
- **Never raises (NFR-R1/R2).** Unexpected failures in the scan, a rule or a fix return an empty result and are
  logged; a failing rule does not affect the other rules, and the committed corpus is exercised by a no-raise
  test. `Diagnostics::Linter#deactivate!` makes a stale registered linter inert after the add-on is released.
- **Testing.** Unit suites cover the scanner, suppression, budget, type walker, every rule, the linter's error
  isolation and the fix builders; `test_linter_lsp.rb` pulls diagnostics through the real test server (including
  require-listing, suppression and recompute-after-edit), and `test_patch_lsp`/`test_linter_lsp` cover the quick
  fixes through `textDocument/codeAction`.

---

## 11. Milestone M6 — Rubydex backend (Ruby LSP 0.27)

**Goal:** Work the same on Ruby LSP 0.27 as on 0.26. **Timing depends on D1.** This can run in parallel from M2 onward, and it must ship before, or soon after, 0.27.0 goes stable.

- **FR-M6-01:** Implement the Indexer Adapter on top of Rubydex. Comments come from the definitions Rubydex returns, and constants and ancestors from its resolved graph.
- **FR-M6-02:** Check whether any add-on API changed between 0.26 and 0.27 (factory method signatures, response builders, node context) and adapt.
- **FR-M6-03:** Widen the `depend_on_ruby_lsp!` range to include 0.27, and add 0.27 to the CI matrix.
- **FR-M6-04:** Run the full test suite against both backends and get identical results. Document any intended differences.
- **FR-M6-05:** Decide when to drop support for 0.26.x (D1).

### 11.1 M6 implementation notes (2026-09-24)

- **Backend selection (FR-M6-01/03).** `lib/ruby_lsp_yard/indexer.rb` requires exactly one backend based on
  `RubyLsp::VERSION`: `RubyIndexerAdapter` below 0.27, `RubydexAdapter` at 0.27+ (0.27 removed `RubyIndexer` from
  the load path). `Indexer.for(global_state)` reads `global_state.index` or `global_state.graph`;
  `Indexer.wrap(backend)` and `Indexer.adapter_class` keep tests and benchmarks backend neutral. The supported
  range is now `>= 0.26.0, < 0.28.0`, and `gemfiles/ruby_lsp_0.27.gemfile` pins `ruby-lsp 0.27.0.beta5` (with
  Rubydex 0.4.1) as a second CI matrix leg.
- **Rubydex mapping and normalization (FR-M6-01).** `RubydexAdapter` wraps `Rubydex::Graph`:
  `graph[name]`/`find_member("name()")` for method, attribute and constant definitions;
  `Namespace#ancestors` + `#members` for `methods_of`/`completion_candidates` (the walk includes private methods,
  which the add-on filters itself, keeps the method when a member carries both a real method and an `attr_*`
  definition, and synthesizes writers from `AttrWriterDefinition`/`AttrAccessorDefinition` because Rubydex names
  attribute members after the reader); `complete_expression` and
  `complete_namespace_access` for `constant_candidates`; and `resolve_constant` with `<...>` nesting sanitization
  plus a top-level fallback (Rubydex does not fall back when a qualified name is unresolvable relative to the
  nesting). Names leaving the adapter keep the RubyIndexer spelling: `Foo::<Foo>` becomes `Foo::<Class:Foo>`,
  comments are joined into one `#`-stripped string, namespace definitions report a `nil` owner (as `RubyIndexer`
  does, which directive discovery depends on), and ancestors backed only by `rubydex:built-in` definitions
  (`Object`, `Kernel`, `BasicObject` when core was not indexed) are dropped.
- **Host API deltas (FR-M6-02).** The add-on hook set (completion, hover, definition, code lens, formatter/linter
  registration, file watching) and the patched request signatures (`Completion`, `Hover`, `Definition`,
  `CodeActions#initialize(document, range, context)`, `ClientCapabilities#apply_client_capabilities`) are unchanged
  in 0.27.0.beta5, so the M4 patch runs as-is and `Patch::TESTED_VERSIONS` gained `0.27.0.beta5`.
  `NodeContext#surrounding_method` changed from a name String to a `MethodDef` (`name`/`receiver`) and singleton
  nesting markers changed from `<Class:Foo>` to `<Foo>`; the new `HostContext` normalizes both shapes for the
  inference engine and the completion listener and, on 0.26, recovers the method receiver from the innermost def
  node so `def Foo.bar` is a singleton scope on both backends. The host `TypeInferrer` now returns singleton type
  names as `Foo::<Foo>`; `Engine#host_resolution` accepts both marker spellings, and comment nodes are still
  reachable through `@parse_result.comments`. Signature help and inlay hints still have no add-on hook in 0.27 (the
  §5.1 audit is otherwise unchanged).
- **Identical results and intended differences (FR-M6-04).** The full suite passes on both backends (413
  runs/1267 assertions on 0.26.11, 416/1280 on 0.27.0.beta5); the backend-specific adapter tests are gated so each
  gemfile exercises its own implementation against the same `test/support/adapter_contract.rb`. Deliberate
  differences: Rubydex reports built-in ancestor placeholders and authoring/attribute details differently, all of
  which the adapter normalizes away; `ENRICHMENT_LIMIT` was raised from 100 to 300 because Rubydex exposes the
  whole ancestor chain for core classes (String has ~270 completion candidates, ~7 ms warm), so truncation had
  become dependent on backend member ordering.
- **FR-M6-05 (D1).** 0.26 stays supported. The drop decision remains two minor releases after 0.27.0 stable; with
  the version-gated adapter and the separate gemfile, dropping it is a gemfile/workflow removal plus a
  `TESTED_VERSIONS` edit.

---

## 12. Milestone M7 — Advanced directives & ecosystem compatibility

**Goal:** Support DSL-heavy code through macros and domains, and offer a smooth path for Solargraph users.

- **FR-M7-01: `@!macro`**
  - Named macros, `[attach]` macros and `[new]` macros.
  - Positional interpolation (`$0`, `$1`…, `$*`, ranges) as defined by YARD.
  - Expansion happens after indexing. A macro is applied only to calls that resolve to the method where the macro was defined (the same rule Solargraph uses).
  - Macros inherited through `include`, `extend` and superclasses.
  - Macros that reference other macros, with cycle detection.
  - Only macros whose expansion contains `@!method`, `@!attribute` or `@!parse` produce new definitions.
- **FR-M7-02: `@!domain`.** Makes a DSL namespace's methods available as implicit-`self` completions within that scope.
- **FR-M7-03: Solargraph compatibility** (depending on D6):
  - read `.solargraph.yml` `domains` and `require` hints
  - `@type` inline annotations, if not already added in M2
- **FR-M7-04:** `rbs-inline` (`#:`) comments as a second source of types (D5).

### 12.1 M7 implementation notes (2026-09-24)

- **`@!macro` (FR-M7-01).** `TagExtractor` turns YARD's `MacroDirective` into a `:macro` raw directive (name,
  flags, data). Expansion is the add-on's own `Macros::Expander`, a faithful port of `MacroObject.expand`
  (`$0..$N`, `${N-M}` ranges with negative indexes, `$*`, `\$`, joined with `", "`), so the YARD Registry is never
  touched (D2). Named macros are catalogued lazily from `all_definitions` (a new adapter method backed by
  `RubyIndexer` entries and Rubydex declarations), not by re-parsing files; attach macros are read from the
  comments of the method each DSL call resolves to, which makes `include`/`extend`/superclass inheritance fall
  out of the existing ancestor walk. Call sites are discovered by parsing the owner's defining files
  (`constant_definitions` URIs) and walking class-level calls, mirroring the diagnostics scanner. Only
  `@!method`/`@!attribute`/`@!parse` in the expansion create definitions; they are built with the shared
  `Documentation::SignatureBuilder`, which was extracted from `SignatureStore` for this purpose. Expansion
  recurses per invocation with per-chain cycle detection and an iteration cap (NFR-R3), so a macro used twice in
  one docstring expands twice, and attached-macro data is run through named-macro expansion before directives are
  applied. Named macros defined only inside gems are found when their target method is resolved but are not
  catalogued globally; this is documented in the README.
- **`@!domain` (FR-M7-02).** YARD drops `@!domain`, so it is scanned from raw comment text and stored as a
  `:domain` raw directive. `Domains::Registry` maps a namespace to its domain type expressions (from its own
  comments and from `.solargraph.yml`), parsing them with the existing `Types::Parser` against the declaring
  namespace's nesting: `Class<X>` becomes a singleton context, `X` an instance context, and comma/union lists are
  flattened. The completion listener now handles implicit-receiver calls (previously ignored) and emits the
  domain members, deduplicating against the host's own implicit-`self` items (FR-M2-17).
- **`@type` (FR-M2-13, D6).** The M2 objection (comments are not in the AST, disk reads are stale) is resolved
  with the M4 patch: the patched Completion/Hover/Definition requests pass the live `RubyDocument` to
  `Engine#with_document`, and the diagnostics linter does the same around its run. `Inference::Annotations`
  parses the comment block immediately above a write node, and `ScopeIndex` now records the write node alongside
  the assignment's value so locals and instance variables use the annotation instead of the inferred RHS type.
  Without the patch (or outside a request) inference sees no document and behaves as before.
- **`rbs collection` (FR-M3-07).** `Rbs::Loader` accepts the workspace path, searches it and its parents for
  `rbs_collection.yaml`, and — when the lockfile exists — adds the collection through
  `EnvironmentLoader#add_collection` before the environment is built. Collection signatures flow through
  `Rbs::Source`, so RBS-wins-over-YARD (D5) applies to gem methods as well as core ones. A broken collection is
  logged and skipped: the loader retries without the collection, then without stdlib, then core-only, so
  collection files that fail to parse cannot take core/stdlib signatures down with them.
- **`rbs-inline` (FR-M7-04, D5).** `rbs-inline ~> 0.14` is a runtime dependency (which tightens the `rbs`
  constraint to `~> 4.0`). `Rbs::Inline` lazily parses files whose source contains the `rbs_inline:` magic
  comment using `RBS::Inline::Parser`/`Writer` and the standard `RBS::Parser`, converts declarations with the M3
  `Converter` (parameters and blocks via a `FunctionSignature` module shared with `Rbs::Source`), and caches per
  path until watched files change. `Rbs::Inline` receives the loader, so aliases and interfaces among the
  annotations resolve against the loaded environment; because standalone inline declarations carry relative type
  names, they are absolutized before the environment lookup. A converter built while the environment was still
  loading is dropped together with the file cache when it becomes ready. `SignatureStore` consults it inside
  `signature_from_definition`, so inline signatures outrank the file's YARD comments; core RBS still answers
  first for core owners. The gem-cache schema does not change because inline signatures are never persisted.
- **Settings and adapter surface.** `enableMacros`, `enableDomains`, `enableSolargraph` and `enableInlineTypes`
  were added (all default on, read at activation like the other feature toggles). The adapter gained
  `all_definitions`; both backends implement it and the shared contract covers it. Rubydex namespace declarations
  normalize to a `nil` owner in `all_definitions` to match `RubyIndexer` (FR-M6-04).
- **Testing.** Unit suites cover the expander (including output parity with `YARD::CodeObjects::MacroObject`),
  the macro catalog/store, the domain registry, `.solargraph.yml`, annotations, the collection loader and the
  inline source; LSP integration tests cover macro completion/hover/definition, domain completion, inline `@type`
  and `rbs-inline`/collection precedence on both backends (`0.26.11` and `0.27.0.beta5`).

---

## 13. Open decisions

| ID | Decision | Options | Proposed default |
|---|---|---|---|
| **D1** ✅ | Which indexer to target first | **Decided:** 0.26/`RubyIndexer` first behind the adapter; Rubydex backend in M6 (done, §11.1) | *Still open:* when to drop 0.26 (proposed: two minor releases after 0.27 stable) |
| **D2** ✅ | YARD parsing dependency | **Decided:** `yard` gem as a runtime dependency, using only its docstring parser (not the Registry or `yardoc`) | Type expressions still need our own parser (FR-M1-07), since YARD stores types as plain strings |
| **D3** ✅ | How to get completion inside comments (M4) | **Decided:** Monkeypatch only, with a version check (FR-M4-P1 to P6) | No upstream proposal planned |
| **D4** | Target audience | Plain Ruby only · Rails-aware (coexist with ruby-lsp-rails, understand ActiveRecord DSL docs) | Plain Ruby first, Rails tested for compatibility |
| **D5** ✅ | Coexisting with Sorbet and RBS | **Decided:** Turn off in Sorbet-typed files; where RBS and YARD both describe a method, RBS wins | *Resolved in M7:* rbs-inline support (FR-M7-04) and `rbs collection` gem signatures (FR-M3-07) are implemented (§12.1) |
| **D6** ✅ | How closely to match Solargraph | None · `@type` inline only · `@type` + `.solargraph.yml` domains | **Decided:** `@type` inline plus `.solargraph.yml` domains, implemented in M7 (§12.1); `require` hints are informational |
| **D7** | Completion when the receiver type is unknown; handling `nil` and `Object` | Show nothing · Leave it to Ruby LSP's default behavior · Guess from method names | Leave it to Ruby LSP; leave `nil` out of unions; treat `Object` as unknown |
| **D8** | How much inference follows control flow | Assignments only (union) · Narrowing on `nil` checks, `is_a?` and `case`/`when` | Union in M2; narrowing as a later M3 stretch goal |
| **D9** ✅ | Which gems to read and where to cache | All bundled gems · An allowlist · None · Cache in `.ruby-lsp/` vs `~/.cache` | **Decided:** every gem the host indexes (Ruby LSP's exclusions apply by construction); cache in `~/.cache/ruby-lsp-yard/<schema>/` shared across projects, keyed by gem name/version, invalidated by a `Gemfile.lock` digest (§8.1) |
| **D10** ✅ | Diagnostics defaults and suppression syntax | See the table in §10 | **Decided:** severities as in the §10 table (four rules default to off); `# yard:disable Rule[, Rule...]` in a definition's comment block, bare `# yard:disable` for all rules, per definition only (§10.1) |
| **D11** ✅ | Minimum Ruby version | **Decided:** 3.4 (3.1–3.3 dropped; diverges from Ruby LSP's own minimum, which is lower) | — |
| **D12** | Gem name and license | `ruby-lsp-yard` · other | `ruby-lsp-yard`, MIT (check the name is free on RubyGems) |
| **D13** | Hover layout | Typed signature only · Signature + a table of tags · Replace Ruby LSP's docs section | Typed signature + `@raise`/`@deprecated`/`@overload` |
| **D14** | Inlay hints | Include in M2 (off by default) · Leave out | Include, off by default, if the API allows (🔍) |

---

## 14. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Add-on API breaks in 0.27 | High | Adapter layer, pinned version ranges, testing against betas early (M6) |
| The comment-completion monkeypatch breaks on a Ruby LSP upgrade (especially the 0.27 request rewrite) | High | Version allowlist, tests for each version, M4 switches off on its own when unsupported (FR-M4-P2 to P5) |
| Adding `yard` to users' bundles conflicts with a pinned `yard` version | Low | Use a wide version constraint; rely only on the stable docstring parser API |
| Duplicate or conflicting results with Ruby LSP's own listeners | Medium | Deduplication in FR-M2-17; only emit for receivers Ruby LSP can't resolve |
| Parsing gem docstrings slows startup | Medium | Lazy parsing, disk cache, background warm-up |
| YARD types are often loose or wrong in real code | High | Treat YARD types as hints, never report errors from them by default, and fall back to `Unknown` |
| Some features aren't available to add-ons | Medium | FR-M0-05 audit in M0; upstream requests or descoping |
