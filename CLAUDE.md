# tula — Claude Code Instructions

## Identity

`tula` (तुला — *balance / scale*) — AGNOS's **sovereign weight-file format**: a
typed, mmap-friendly tensor manifest + payload with a sigil-signable header.
The safetensors/GGUF analog behind the Type-3 pretrained-import path. Pure
Cyrius, no external code. GPL-3.0-only.

**Scope — what tula IS and IS NOT:**
- IS: the on-disk **codec** (serialize/parse tensors + a signed header).
- IS NOT: a model **store** (that is the control-plane's, over vahana/sankoch +
  sigil); IS NOT the **importer** (that is `anukulana`, the Type-3 reference);
  IS NOT a tensor library (that is `rosnet`).

## Structure

- `src/lib.cyr` — the include chain. **Stdlib includes live ONLY here.** Domain
  modules (`src/error.cyr`, `src/format.cyr`) are **flat** (no includes) so
  `cyrius distlib` concatenates a compile-clean `dist/tula.cyr`. Do not add
  stdlib includes to domain modules; do not reorder `[lib].modules` without
  re-running `cyrius distlib`.
- `programs/smoke.cyr` — link-check entry (no CLI binary; tula is a lib).
- `tests/tcyr/*.tcyr` — standalone CPU suites (own `main` + `assert_summary`).

## Build / test

```sh
make build   # cyrius build programs/smoke.cyr build/tula_smoke
make test    # cyrius test tests/tcyr/*.tcyr
make dist    # cyrius distlib -> dist/tula.cyr
```

- **Never `cat file | cycc`** — always `cyrius build`. `lib/` is populated by
  `cyrius deps` from `[deps].stdlib`; it is a build artifact (gitignored),
  never committed, never a symlink to a cyrius checkout.
- Cyrius pin lives in `cyrius.cyml` (`cyrius = "..."`, single source of truth) —
  read it there, don't inline the number here.
- Format fields are i64-aligned; use `store64`/`load64` + `store8`/`load8` +
  `memcpy` (all available). Avoid module-scope `var X[N]` array footguns.

## Current state (pointers — don't inline volatile state)

- **Live status** (version, test counts, cycle) → [`docs/development/state.md`](docs/development/state.md).
- **Release history** → [`CHANGELOG.md`](CHANGELOG.md).
- **Public API + stability** → [`docs/api.md`](docs/api.md) + [`STABILITY.md`](STABILITY.md)
  (the surface + on-disk format v1 are frozen at 1.0 — [ADR 0003](docs/adr/0003-api-freeze-at-v1.md)).

## Docs

- **Decisions** → [`docs/adr/`](docs/adr/) (0001 scope · 0002 sidecar scales · 0003 API freeze).
- **Code invariants** → [`docs/architecture/`](docs/architecture/) (001 flat modules · 002 validated-buffer trust gate).
- **How-tos** → [`docs/guides/`](docs/guides/) · **runnable examples** → [`examples/`](examples/) (indexed at [`docs/examples/`](docs/examples/)).
- **Roadmap** → [`docs/development/roadmap.md`](docs/development/roadmap.md) · **benchmarks** → [`docs/benchmarks.md`](docs/benchmarks.md) · **security** → [`SECURITY.md`](SECURITY.md) + [`docs/audit/`](docs/audit/).

## Rules

- **Do not commit, push, or tag** — the maintainer handles all git.
- **Never use the `gh` CLI** — reach the GitHub API via `curl` if needed.
- Structure came from `cyrius init` — don't hand-roll the root files or docs
  skeleton; fix the template and re-propagate.
