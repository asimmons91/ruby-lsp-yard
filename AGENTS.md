# AGENTS.md

## What this is
Ruby LSP add-on (working name `ruby-lsp-yard`) that reads YARD `@param`/`@return` tags as type annotations for completion, hover, signature help and definition. The repo is past the `bundle gem` scaffold only in namespace: the discovery entrypoint `lib/ruby_lsp/ruby_lsp_yard/addon.rb` defines a stub `RubyLsp::Yard::Addon` (gated by `depend_on_ruby_lsp!("~> 0.26.0")`); no features are implemented.

`docs/requirements_v1.md` is the accepted V1 spec (architecture, milestones M0–M7, open decisions D1–D14) and the source of truth for scope and design. Read it before implementing anything. Key decisions already made: `yard` gem is a runtime dependency (parsing only, no Registry); all indexer access goes through an adapter because 0.26 has `RubyIndexer` and 0.27 has Rubydex; completion inside comments requires a version-guarded monkeypatch (D3); where RBS and YARD both describe a method, RBS wins.

## Commands
- Setup: `bin/setup` (i.e. `bundle install`)
- Full check: `bundle exec rake` — runs `test` then `standard`; this is what CI runs (`.github/workflows/main.yml`, Ruby 3.2 and 4.0)
- Tests: `bundle exec rake test`
  - single file: `bundle exec rake test TEST=test/ruby_lsp/ruby_lsp_yard/test_addon.rb`
  - single test: add `TESTOPTS="--name=test_it_has_a_version_number"`
- Lint: `bundle exec rake standard`; autofix: `bundle exec standardrb --fix`

## Gotchas
- `sig/ruby_lsp/yard.rbs` is scaffold RBS (single file; path mirrors the module, not `lib`); no typecheck runs in CI.
- Ruby target is >= 3.2 (gemspec, `.standard.yml`) but CI only exercises 3.2 and 4.0.
- The add-on entrypoint calls `RubyLsp::Addon.depend_on_ruby_lsp!("~> 0.26.0")`; it will not activate against 0.27 (Rubydex) until M6.
- `ruby-lsp` is a development dependency (Gemfile), not a runtime dependency; add-ons declare compatibility with `depend_on_ruby_lsp!` instead (FR-M0-02).
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
