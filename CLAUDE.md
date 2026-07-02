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
- Cyrius pin: `cyrius = "6.3.26"` in `cyrius.cyml` (single source of truth).
- Format fields are i64-aligned; use `store64`/`load64` + `store8`/`load8` +
  `memcpy` (all available). Avoid module-scope `var X[N]` array footguns.

## Roadmap (see docs/development/roadmap.md)

M0 format + in-memory round-trip (**done**) → M0b sigil-signed header → M1 file
I/O (mmap read + write-to-disk) → M2 ternary/nf4 payload helpers → v1.0 (API
freeze + fuzz + bench). Do not commit or push — the user handles all git.
