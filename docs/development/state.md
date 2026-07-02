# tula — Current State

> **Last refresh**: 2026-07-01 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**1.0.0 — API frozen 2026-07-01** (M0–M5; format **v1**). Prior cut: 0.1.0 (M0 +
M0b: format + round-trip + Ed25519 signed header). **v1.0 added M1–M5.** M1 —
file I/O: `tula_write_file`
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

VERSION is **1.0.0** (`tula_version_int()` returns `10000`). Post-1.0 work
accretes under a fresh CHANGELOG `[Unreleased]` and is additive-only (SemVer);
the maintainer bumps VERSION + renames the section + tags at each subsequent cut.

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

**1.0.0 is cut at the file level** — VERSION `1.0.0`, CHANGELOG `[1.0.0]`,
`tula_version_int()` → `10000`, docs rolled, all criteria checked. **The only
step left is the maintainer's git action** (Claude does not run git): tag `1.0.0`
(the `release.yml` workflow fires on the tag) after confirming the `sigil` tag
(3.9.9) exists on GitHub for CI/release resolution.

Post-1.0, work accretes under `[Unreleased]` and is additive-only. A future bite
could round-trip a real attn11 checkpoint through `tula_*_file` once attn11's
checkpoint reader lands.
