# tula — Current State

> **Last refresh**: 2026-07-01 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**0.1.0** — **unreleased** (not yet tagged). **M0 + M0b: weight-file format,
in-memory round-trip, and the Ed25519 signed header.** Header + typed 144-byte
manifest entries + 8-byte-aligned payload; builder/reader; find-by-name;
magic/version validation; **sigil Ed25519 sign/verify** over the file content
(`sig_off`/`sig_len` in the header; signature appended). **30 assertions**
across 2 suites (`roundtrip.tcyr` 22 + `sign.tcyr` 8), all green. Builds + tests
warning-clean.

No released tags yet. **The 0.1.0 tag (M0 milestone complete) is ready to cut** —
CI + release workflows are in place; a `0.1.0` tag triggers the release.

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

**M1** — file I/O: `tula_write_file` / `tula_open_file` (mmap), round-trip a real
attn11 checkpoint through a real file, bit-identical. Then M2 (ternary/nf4 payload
helpers) → v1.0 (API freeze + fuzz + bench). See `roadmap.md`.
