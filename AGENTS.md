# AGENTS.md

## What this is
Ruby LSP add-on (working name `ruby-lsp-yard`) that reads YARD `@param`/`@return` tags as type annotations for completion, hover, signature help and definition. Milestones M0–M3 are implemented: the add-on activates through `lib/ruby_lsp/ruby_lsp_yard/addon.rb` (gated by `depend_on_ruby_lsp!("~> 0.26.0")`), all host-indexer access goes through `lib/ruby_lsp_yard/indexer/` (adapter interface + `RubyIndexerAdapter`), YARD parsing and the signature store live in `lib/ruby_lsp_yard/documentation/` and `signature_store.rb`, the M2 inference engine in `lib/ruby_lsp_yard/inference/`, the M3 RBS bridge and gem cache in `lib/ruby_lsp_yard/rbs/` and `lib/ruby_lsp_yard/gems/`, and the hover/completion/definition listeners in `lib/ruby_lsp_yard/listeners/`. M4–M7 (authoring, diagnostics, Rubydex, macros) are not implemented yet.

`docs/requirements_v1.md` is the accepted V1 spec (architecture, milestones M0–M7, open decisions D1–D14) and the source of truth for scope and design. Read it before implementing anything. Key decisions already made: `yard` gem is a runtime dependency (parsing only, no Registry); all indexer access goes through an adapter because 0.26 has `RubyIndexer` and 0.27 has Rubydex; completion inside comments requires a version-guarded monkeypatch (D3); where RBS and YARD both describe a method, RBS wins. M3's implementation notes live in §8.1.

## Commands
- Setup: `bin/setup` (i.e. `bundle install`); per-version bundles: `BUNDLE_GEMFILE=gemfiles/ruby_lsp_0.26.gemfile bundle install`
- Full check: `bundle exec rake` — runs `test` then `standard`; this is what CI runs (`.github/workflows/main.yml`, Ruby 3.4/4.0 × `gemfiles/ruby_lsp_0.26.gemfile`)
- Tests: `bundle exec rake test`
  - single file: `bundle exec rake test TEST=test/ruby_lsp/ruby_lsp_yard/test_addon.rb`
  - single test: add `TESTOPTS="--name=test_it_has_a_version_number"`
- Lint: `bundle exec rake standard`; autofix: `bundle exec standardrb --fix`

## Gotchas
- `Gemfile.common` holds the shared development dependencies. Each supported `ruby-lsp` minor gets its own `gemfiles/ruby_lsp_*.gemfile` and CI matrix leg; widening the supported range (M6) means adding a file there, not editing `Gemfile`.
- `sig/ruby_lsp/yard.rbs` is scaffold RBS (single file; path mirrors the module, not `lib`); no typecheck runs in CI.
- Ruby target is >= 3.4 (gemspec, `.standard.yml`); CI exercises 3.4 and 4.0.
- The add-on entrypoint calls `RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")`; it will not activate against 0.27 (Rubydex) until M6.
- `ruby-lsp` is a development dependency (Gemfile/gemfiles), not a runtime dependency; add-ons declare compatibility with `depend_on_ruby_lsp!` instead (FR-M0-02).
- Backends must pass `test/support/adapter_contract.rb`; the Rubydex backend (M6) includes the same module. Fixture files are real files under `test/fixtures/` because indexer entries read comments from disk.
- M3 adds `rbs` as a runtime dependency. `lib/ruby_lsp_yard/rbs/` builds its own `RBS::Environment` (core + all stdlib) in a background thread because `RubyIndexer`'s `RBSIndexer` strips type information; `lib/ruby_lsp_yard/rbs/source.rb` is the only code that queries `RBS::DefinitionBuilder`, and lookups are memoized per class. This code is host-version independent so Rubydex (M6) reuses it.
- Gem signatures are cached at `~/.cache/ruby-lsp-yard/<schema>/<gem>-<version>.bin` (root injectable; tests pass a temp dir) and invalidated by a `Gemfile.lock` digest. Writes are batched (first signature immediate, then every 32 writes/2 s) and flushed on `deactivate`. `Marshal.load` has no class allowlist on Ruby 3.4/4.0, so the payload is trusted user-local state. FR-M3-07 (`rbs collection`) is deferred to M7.
- The signature store subscribes to the RBS loader and drops its caches when the environment becomes ready, so lookups served during the background load window are not pinned to their fallback. LSP tests that assert core types call `index_core(server)` and then `wait_for_rbs(server)`. `test/corpus/test_m3_corpus.rb` is the M3 acceptance corpus; `benchmark/rbs.rb` measures environment build and lookup latency.
- The gemspec builds its file list from `git ls-files`, so new files must be tracked before `rake build`/`install`.

## Git Workflow
* Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for all commit messages: `<type>[optional scope]: <description>`
* **Allowed Types**: 
  * `feat` (new feature)
  * `fix` (bug fix)
  * `docs` (documentation)
  * `refactor` (code restructuring)
  * `test` (adding/updating tests)
  * `chore` (tooling/dependencies)
* **Example**: `git commit -m "feat(api): add user authentication endpoint"`
* **Validation**: Run `npx commitlint --from HEAD~1 --to HEAD` before finalizing changes if commitlint is configured.
