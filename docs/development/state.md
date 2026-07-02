# tula — Current State

> **Last refresh**: 2026-07-01 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**0.1.0 — released 2026-07-01** (M0 + M0b: format + round-trip + Ed25519 signed
header). **`[Unreleased]` now adds M1 — file I/O**: `tula_write_file` /
`tula_read_file` (heap) / `tula_open_mmap` (zero-copy) / `tula_close_mmap`; tula
files are self-describing so reads need no `stat()`. **46 assertions** across 3
suites (`roundtrip.tcyr` 22 + `sign.tcyr` 8 + `fileio.tcyr` 16), all green; builds
+ tests warning-clean.

VERSION stays **0.1.0** until the next cut — the maintainer bumps VERSION,
renames the CHANGELOG `[Unreleased]` section to `[0.2.0]`, and tags.

## Toolchain

Cyrius pin **6.3.27** (`cyrius.cyml`). Deps: the sigil-consumer stdlib set +
**sigil** (Ed25519). Local dev resolves sigil via `path = "../sigil"`; CI/release
resolve via `[deps.sigil]` **git+tag** — so **sigil 3.9.9 must be tagged on
GitHub** for CI + the release to pass.

## Build artifacts

- `programs/smoke.cyr` → `build/tula_smoke` (link-check).
- `dist/tula.cyr` — the distlib bundle consumers pull via `[deps.tula]`
  (regenerate with `make dist`; leaves `ed25519_*` unresolved — consumer supplies
  sigil, the standard consumer-bundle pattern). `cyrius.lock` is gitignored (CI
  re-resolves fresh).
- CI (`.github/workflows/ci.yml`) + release (`.github/workflows/release.yml`).

## Next

**M2** — ternary/nf4 payload helpers (tentib + anukūlana/QLoRA interop). Then
v1.0 (API freeze + `docs/api.md` + fuzz + bench + a downstream consumer). A
future bite could round-trip a real attn11 checkpoint through `tula_*_file` once
attn11's checkpoint reader is available. See `roadmap.md`.
