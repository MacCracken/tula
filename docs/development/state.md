# tula — Current State

> **Last refresh**: 2026-11-04 | **Cadence**: every release.
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

VERSION is **1.1.2** (`tula_version_int()` returns `10102`). 1.0.1–1.1.1 are
toolchain/dep realigns. **1.1.2 is the P(-1) pass**
([audit](../audit/2026-11-04-audit.md)): ten reproduced defects fixed (worst: a
truncated file crashed `tula_open_mmap` with SIGBUS), hot paths 1.2–11.6× faster
with byte-identical output, and no API or format change. Post-1.0 work
accretes under a fresh CHANGELOG `[Unreleased]` and is additive-only (SemVer);
the maintainer bumps VERSION + renames the section + tags at each subsequent cut.

## Tests, fuzz, gates (1.1.2)

**178 assertions** across 6 suites, all green: `builder.tcyr` 38, `dtype.tcyr` 50,
`fileio.tcyr` 30, `hardening.tcyr` 30, `roundtrip.tcyr` 22, `sign.tcyr` 8. `dtype`
and `builder` include differential tests against the 1.1.1 implementations.
`make fuzz`: 2,003,000 iterations with every buffer ending at a `PROT_NONE` guard
page, plus a payload-guard + unpack phase (40,472 entries), 0 faults. `fmt` /
`lint` / `vet` / `deny` clean; `cyrius doc --check src/*.cyr`: 0 undocumented.

## Toolchain

Cyrius pin **6.7.18** (`cyrius.cyml`). Deps: the sigil-consumer stdlib set +
**sigil 3.13.15** (Ed25519), sigil's latest release and the copy 6.7.18 bundles. Every build resolves
`[deps.sigil]` **git+tag**, local and CI alike (cyrius ≥ 6.7.6, git first). The sigil
tag must exist on GitHub for CI + the release to pass.

**Local sigil work:** `CYRIUS_LOCAL=1` (or `--local`) builds the `../sigil` working
tree under `build/local-deps/`; `lib/` and `cyrius.lock` stay the tag's. Without the
switch a build prints one `hint:` line naming the unused checkout.

**Pin history:** 6.3.27 → 6.5.27 (2026-08-17) → 6.6.2 (2026-09-11) → 6.6.20
(2026-11-04, 1.0.3) → 6.7.9 (2026-11-04, 1.1.0) → **6.7.18** (2026-11-04, 1.1.1).
Since 6.6.18, `cyrius distlib` writes a sidecar only for leaves the bundle itself needs.
tula needs none beyond what sigil's sidecar brings, so there is no `dist/tula.deps`.

**Smoke binary: 590,952 B** (~100 KB code, 488 KB data). Most of the data is bayan's
`lib/unicode/` tables, which sigil's bundle pulls in. DCE can't drop global initializers,
and tula itself makes no bayan calls. It shrinks when sigil's open issue
`2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md` lands.

## Build artifacts

- `programs/smoke.cyr` → `build/tula_smoke` (link-check).
- `programs/fuzz.cyr` → `build/tula_fuzz` (`make fuzz`) + `programs/bench.cyr` →
  `build/tula_bench` (`make bench`; writes `build/tula_bench.tula`) +
  `examples/consumer.cyr` → `build/tula_consumer` (`make example`, a CI gate).
  Tests and the example write their files under `build/`.
- `dist/tula.cyr` — the distlib bundle consumers pull via `[deps.tula]`
  (regenerate with `make dist`; leaves `ed25519_*` unresolved — consumer supplies
  sigil, the standard consumer-bundle pattern). `cyrius.lock` is gitignored (CI
  re-resolves fresh).
- CI (`.github/workflows/ci.yml`) + release (`.github/workflows/release.yml`).

## Next

**1.2.0 — real checkpoints** ([roadmap](roadmap.md)): a sized builder (real models
pass 256 tensors), a checked add that refuses name collisions, a strict validator
(overlap / duplicates / shape-vs-size), a signature-required verify, and a
quant-sidecar check — all additive. 1.3.0 takes long names and F32/F16/BF16; 1.4.0
the streaming writer for files over 2 GiB.
