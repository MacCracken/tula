# 0003 — Freeze the public API and on-disk format at 1.0

**Status**: Accepted
**Date**: 2026-07-01

## Context

tula reached feature completeness across the M1–M5 roadmap (file I/O, dtype
payload helpers, reader hardening, fuzz + bench, security audit) with a green
downstream consumer. Unlike a reference binary, tula is a **conventional library
with many consumers** — `rupantara` / `anukulana`, the murti load-seam, and the
control-plane checkpoint store all pull `dist/tula.cyr` and, more importantly,
depend on the **on-disk format**: files written today must read years from now.
The remaining gate to 1.0 is a stability commitment those consumers can build on.

## Decision

Freeze, as of **1.0.0**, two things:

1. **The on-disk format (v1)** — the 64-byte header and 144-byte manifest entry
   layout, field offsets, `TULA_MAGIC` / `TULA_VERSION`, the dtype codes, and the
   Ed25519 signed-header scheme. A layout change is a `TULA_VERSION` bump — a
   MAJOR, coordinated event (the sidecar-scale design in
   [ADR 0002](0002-quant-scales-as-sidecar-tensors.md) exists precisely to *avoid*
   one during the M2 dtype work).
2. **The documented public surface** in [`docs/api.md`](../api.md) — the builder,
   reader, accessors, signature, file-I/O, and dtype helpers, with their
   signatures, semantics, and the public constants (`TULA_DT_*`, `TULA_SIG_*`, the
   `TULA_ERR_*` codes and values, and the format constants).

Out of scope: the internal helpers not listed in `docs/api.md` (e.g.
`tula_align8`, `tula_name_write`, `tula_serialize`, `tula_hdr_total`,
`tula_nf4_nearest`); benchmark numbers; the exact `TULA_ERR_*` a given malformed
input returns (rejection is stable; the label may sharpen). The full policy —
what PATCH / MINOR / MAJOR each promise — lives in [`STABILITY.md`](../../STABILITY.md).

## Consequences

- **Positive** — consumers can pin `1.x` and rely on both the format and the API;
  1.0.0 becomes a clean cut (version bump + a doc pass) rather than a scramble;
  the frozen format decouples tula's release cadence from its consumers'.
- **Negative** — we now own backward compatibility. Adding a parameter to a frozen
  function, or a field to the entry, is a MAJOR bump; future extensions favor
  **new** functions / **new** dtype codes over changed ones, and additive format
  growth (a new dtype) over layout changes.
- **Neutral** — the resource caps (`TULA_READ_MAX_*`) may be *raised* in a MINOR
  release (never lowered) to admit larger real-world files.

## Alternatives considered

- **Stay 0.x indefinitely.** Rejected: consumers are landing and the ecosystem
  needs a stable weight-file codec to build on; perpetual 0.x signals unfinished,
  which is false.
- **Freeze the API but not the format.** Rejected: the format *is* the contract
  for a codec — an unstable on-disk layout makes stored checkpoints worthless.
- **Extend the entry with a scale field before freezing** (rather than sidecar
  tensors). Rejected in [ADR 0002](0002-quant-scales-as-sidecar-tensors.md): it
  fails generality (NF4's per-block scales are an array) and forces a breaking
  format bump right at the freeze.
