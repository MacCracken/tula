# tula — Current State

> **Last refresh**: 2026-07-01 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**0.1.0** — **unreleased** (not yet tagged). **M0: the weight-file format +
in-memory round-trip.** Header + typed 144-byte manifest entries + 8-byte-aligned
payload; builder/reader; find-by-name; magic/version validation. `sig_off`/
`sig_len` reserved (files unsigned in M0). **22 assertions** (1 suite,
`tests/tcyr/roundtrip.tcyr`), all green.

No released tags yet.

## Toolchain

Cyrius pin **6.3.26** (`cyrius.cyml`). Builds + tests clean on 6.3.26. M0 deps
are **stdlib-only** (string/fmt/alloc/io/vec/str/syscalls/assert/bench/args/flags);
`sigil` is added at M0b for the signed header.

## Build artifacts

- `programs/smoke.cyr` → `build/tula_smoke` (link-check, runs + exits 0).
- `dist/tula.cyr` — the distlib bundle consumers pull via `[deps.tula]`
  (regenerate with `make dist`).

## Next

M0b (sigil-signed header) → M1 (file I/O: mmap read + write-to-disk, round-trip
an attn11 checkpoint through a real file). See `roadmap.md`.
