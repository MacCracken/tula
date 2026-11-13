# 0016 — A parallel UINT4 unpack beside `tula_unpack_par`

**Status**: Accepted
**Date**: 2026-11-12

## Context

`tula_unpack_par` (ADR 0012) runs a dtype's serial unpack over slices on several
threads. Its signature has one sidecar pointer, `scales`, enough for every
dtype it covered at 1.9.0. UINT4 (ADR 0015) needs two, its `.scale` and its
`.min`, so 1.12.0 left it out: `tula_unpack_par` returns −1 for UINT4.

A Q4_1 checkpoint therefore unpacks on one thread at ~257 Melem/s, while an
INT4 one reaches ~1,480 at 8 threads. The function's signature is frozen
(STABILITY.md), so it can't gain a parameter.

## Decision

**Add `tula_uint4_unpack_par(codes, scales, mins, n, block, dst, nthreads)`:
`tula_uint4_unpack` on up to `nthreads` threads, with its output bit for bit.**

- **Its arguments are the serial helper's, plus `nthreads`.** The slicing,
  thread handling and refusals are `tula_unpack_par`'s (ADR 0012):
  - slices start on a whole block (twice the block when it is odd), so each
    reads its own scales and minimums;
  - each thread gets at least `TULA_PAR_MIN_CHUNK` elements, and at most
    `TULA_PAR_MAX_THREADS` are used;
  - a thread that fails to start, or a target without real threads, falls back
    to the caller's thread.

  It returns n, or −1, writing nothing, for `n < 0` or `block <= 0`, and 0 for
  `n = 0`.
- **`tula_unpack_par` is unchanged**: it still returns −1 for UINT4.
- **Inside, one slicer serves both calls.** A job carries a second sidecar
  pointer, so the code isn't duplicated.

## Consequences

- **Positive** — Q4_1 loads scale with threads as INT4's do.
- **Negative** — a loader has one more case: UINT4 goes to its own call rather
  than the dtype switch in `tula_unpack_par`.
- **Neutral** — a later two-sidecar dtype (a `.zero` form, say) would get a
  call of its own the same way.

## Alternatives considered

- **A generic `tula_unpack_par2(dtype, src, n, scales, aux, block, dst,
  nthreads)`:** rejected. `aux` would mean a different thing for each dtype
  that ever uses it, and UINT4 is the only one today. A call named for the
  dtype says exactly what its pointers are.
- **Passing both sidecars through `scales`** (a pointer to a two-pointer
  struct, say, for UINT4 only): rejected. It changes what `scales` means for
  one dtype of a frozen call.
