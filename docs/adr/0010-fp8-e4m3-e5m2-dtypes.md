# 0010 — FP8 dtypes: OCP E4M3 and E5M2, converted from f64 without saturation

**Status**: Accepted
**Date**: 2026-11-12

## Context

FP8 checkpoints are now common. Hopper-class inference stores weights as 8-bit
floats with a per-tensor or per-block scale, and several large models ship only
that way. The formats are the two from the OCP 8-bit floating point
specification (OFP8), which PyTorch calls `float8_e4m3fn` and `float8_e5m2` and
safetensors `F8_E4M3` and `F8_E5M2`:

| | E4M3 | E5M2 |
|---|---|---|
| exponent bits, bias | 4, 7 | 5, 15 |
| mantissa bits | 3 | 2 |
| largest finite | 448 | 57,344 |
| smallest subnormal | 2⁻⁹ | 2⁻¹⁶ |
| infinities | none | ±inf (`S.11111.00`) |
| NaN | `S.1111.111` only | `S.11111.{01,10,11}` |

E5M2 is IEEE-like: it is binary16 with 8 fewer mantissa bits. E4M3 isn't: it has
no infinities, its all-ones exponent holds normal values (256 to 448), and only
the all-ones mantissa there is NaN.

New `TULA_DT_*` values are a MINOR (STABILITY.md), and the conversions need the
same care as ADR 0005's. The spec leaves one choice open: what a conversion does
with a value past the largest finite number. It allows saturating to ±max, or
not (NaN for E4M3, inf for E5M2).

## Decision

**Add `TULA_DT_F8_E4M3 = 12` and `TULA_DT_F8_E5M2 = 13`, one byte per element,
with conversions to and from f64 in integer arithmetic, as ADR 0005's.**

- **Storage.** One byte per element, the OCP bit layout, `data_len = nelems`.
  Every byte is a value (NaN included), so strict has no value rule for them,
  only the size.
- **f64 → FP8** (`tula_f64_to_e4m3` / `_e5m2`, `tula_e4m3_pack` / `_e5m2_pack`):
  - Round to nearest, ties to even, **directly from the f64** (no rounding
    through F32 or F16, so there's no double rounding).
  - Subnormals are kept (no flush to zero), and so is the sign of zero.
  - **No saturation.** A value that rounds past the largest finite number
    becomes NaN in E4M3 (so anything over 464, the midpoint between 448 and
    the 480 the NaN pattern would hold) and ±inf in E5M2 (anything from 61,440
    on). ±inf does the same.
  - NaN stays NaN with its sign. E5M2 keeps the top payload bit and sets the
    quiet bit, the rule ADR 0005 uses for F16, so the default NaN becomes
    `0x7E`. E4M3 has one NaN per sign.
- **FP8 → f64** (`tula_e4m3_to_f64` / `_e5m2_to_f64`, the `_unpack` helpers) is
  exact. A NaN comes back quiet with its sign: E4M3's as `0x7FFE…` (mantissa
  111, the bits PyTorch's widening gives), E5M2's with its payload kept.
- **E5M2 reuses the shared narrow/widen** of ADR 0005, with (E, M) = (5, 2).
  E4M3 has its own, since its top exponent isn't reserved.

## Consequences

- **Positive** — FP8 checkpoints are stored at their own size, under their own
  dtype. The conversions are checked exhaustively, as F16/BF16 are:
  - every one of the 256 codes of each format round-trips, and the finite ones
    are strictly ordered;
  - every midpoint between neighbours rounds to the even code, and the f64
    values one ulp either side round to their own side;
  - 40,000 random values agree with a brute-force nearest-code oracle.

  Outside the repo, an exact-rational reference written from the spec agreed on
  all 512 decodes and 400,000 encodes. The bytes don't depend on the FP mode.
- **Negative** — a quantizer must scale its values into range first. With no
  saturation, a value past 448 becomes NaN in E4M3, so an out-of-range weight
  is visible rather than silently clipped. The scale itself is a consumer
  convention (ADR 0002 sidecars, or the source checkpoint's own names). Packing
  is a per-element function call (~a few ns each, `docs/benchmarks.md`).
- **Neutral** —
  - A 1.2–1.7 strict validator returns `TULA_ERR_DTYPE` for these codes; its
    plain reader opens and verifies the file as before.
  - For a NaN input, E5M2's bytes can differ from PyTorch's cast, which writes
    `0x7F` for every NaN. Both read back as NaN. Imported FP8 bytes are stored
    as they are, never converted, so this only matters when tula quantizes
    NaNs itself.

## Alternatives considered

- **Saturate to ±max** (the spec's other mode, and an option of NVIDIA's
  conversion instruction): rejected as the only behaviour. It hides an
  out-of-range value as the largest one. Not saturating also matches PyTorch's
  `.to(float8_*)` and IEEE overflow. A quantizer that wants clipping clamps
  first, which is one comparison.
- **Both modes** (a flag, or `_sat` variants): not now. Clamping before the cast
  gives the saturating result, so a second set of functions would be surface
  without a known user. A MINOR can add them.
- **The FNUZ variants** (`float8_e4m3fnuz`, `e5m2fnuz`: bias +1, no negative
  zero, NaN at `0x80`), used by some AMD tooling: left out. The OCP formats are
  the ones checkpoints ship in. Each FNUZ variant would be its own code.
- **Rounding through F16 or F32**: rejected, as in ADR 0005. It double-rounds,
  so some values land on a different code than one rounding from f64 gives.
- **A 256-entry lookup table for unpacking**: not now. It's faster, but it needs
  module state or a table per call, and throughput is 1.9.x's subject.
