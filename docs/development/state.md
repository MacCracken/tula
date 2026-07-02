# tula — Current State

> **Last refresh**: 2026-07-01 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**0.1.0 — released 2026-07-01** (M0 + M0b: format + round-trip + Ed25519 signed
header). **`[Unreleased]` now adds M1–M5.** M1 — file I/O: `tula_write_file`
/ `tula_read_file` (heap) / `tula_open_mmap` (zero-copy) / `tula_close_mmap`; tula
files are self-describing so reads need no `stat()`. M2 — dtype payload helpers
(`src/dtype.cyr`): ternary/int8/NF4 pure pack/unpack; scales stored as sidecar
`"<name>.scale"` tensors (ADR 0002 — **no format-version bump**, the 144B entry
stays frozen). M3 — reader hardening (`tula_validate` + a strict `tula_open`):
untrusted/lying/truncated input rejected with a specific `TULA_ERR_*`, overflow-
safe, resource-capped (2²⁰ tensors / 2⁴⁰ bytes), file readers bomb-guarded before
alloc/mmap. M4 — `programs/fuzz.cyr` (2M+ iters clean, validates M3) +
`programs/bench.cyr` + `docs/benchmarks.md`. M5 — 6-dimension security audit
(`docs/audit/2026-07-01-audit.md`, verdict PASS) + `SECURITY.md`; closed a
consumer-side over-read with `tula_entry_payload_ok`. **105 assertions** across 5
suites (`roundtrip.tcyr` 22 + `sign.tcyr` 8 + `fileio.tcyr` 16 + `dtype.tcyr` 29 +
`hardening.tcyr` 30), all green; builds + tests warning-clean.

VERSION stays **0.1.0** until the next cut — the maintainer bumps VERSION,
renames the CHANGELOG `[Unreleased]` section to `[0.2.0]`, and tags.

## Toolchain

Cyrius pin **6.3.27** (`cyrius.cyml`). Deps: the sigil-consumer stdlib set +
**sigil** (Ed25519). Local dev resolves sigil via `path = "../sigil"`; CI/release
resolve via `[deps.sigil]` **git+tag** — so **sigil 3.9.9 must be tagged on
GitHub** for CI + the release to pass.

## Build artifacts

- `programs/smoke.cyr` → `build/tula_smoke` (link-check).
- `programs/fuzz.cyr` → `build/tula_fuzz` (`make fuzz`) + `programs/bench.cyr` →
  `build/tula_bench` (`make bench`) + `examples/consumer.cyr` →
  `build/tula_consumer` (`make example`, a CI gate).
- `dist/tula.cyr` — the distlib bundle consumers pull via `[deps.tula]`
  (regenerate with `make dist`; leaves `ed25519_*` unresolved — consumer supplies
  sigil, the standard consumer-bundle pattern). `cyrius.lock` is gitignored (CI
  re-resolves fresh).
- CI (`.github/workflows/ci.yml`) + release (`.github/workflows/release.yml`).

## Next

**v1.0 is feature-complete under `[Unreleased]`** (M1–M5 + freeze docs +
consumer): `docs/api.md`, `STABILITY.md`, `docs/audit/2026-07-01-audit.md`,
`SECURITY.md`, `docs/benchmarks.md`, `examples/consumer.cyr`. All v1.0 criteria in
`roadmap.md` are checked. **Remaining = the maintainer's cut only**: bump VERSION
→ 1.0.0, rename the CHANGELOG `[Unreleased]` → `[1.0.0]`, tag (+ confirm the
`sigil` tag exists for CI/release). **At the cut**, also update the
version-coupled helper `tula_version_int()` (`src/format.cyr`, currently returns
`100` for 0.1.0 → `10000`) and its assertion in `roundtrip.tcyr`. A future bite
could round-trip a real attn11 checkpoint through `tula_*_file` once attn11's
checkpoint reader lands.
