# 0011 — INT4: signed 4-bit codes, with blockwise scales in an ADR 0002 sidecar

**Status**: Accepted
**Date**: 2026-11-12

## Context

4-bit integer weights are the most common compact format on the import path:

- **GGUF Q4_0**: blocks of 32 values, one f16 scale `d` each, `value = (q − 8)
  × d` for an unsigned code `q` of 0..15. Its reference quantizer takes `d =
  m / −8`, where `m` is the block's value of largest magnitude, so all 16 codes
  get used.
- **GGUF Q4_1** and **AWQ / GPTQ** are asymmetric: a scale plus a minimum or a
  zero point. Since 1.7.0, GPTQ/AWQ imports store their packed `int32` tensors as
  `TULA_DT_I32` (ADR 0009).
- tula already has **NF4** (QLoRA's codebook), with its per-block f64 scales in
  a `"<name>.scale"` sidecar (ADR 0002).

The roadmap left one question for this ADR. Should INT4 be **blocks with an
inline f16 scale** (one tensor, GGUF-compatible bytes), or **codes plus an ADR
0002 `.scale` sidecar** (tula's existing convention)? The Type-3 importer
(anukulana) asked for the sidecar. It stores Q8_0 that way already, as int8
codes with a per-32 scale tensor, and would store Q4_0 the same.

## Decision

**Add `TULA_DT_INT4 = 14`: signed 4-bit codes, two per byte, with blockwise
scales in the `"<name>.scale"` sidecar.**

- **Storage.** Codes are −8..7 in two's complement. Element 2k is the low
  nibble of byte k and element 2k+1 the high nibble, the order NF4 uses.
  `data_len = ceil(nelems / 2)`. With an odd count, the last byte's high nibble
  is zero, and **`tula_validate_strict` rejects a nonzero one** with
  `TULA_ERR_VALUE` (19, ADR 0009), so one tensor has one encoding.
- **Scales** follow ADR 0002: `"<name>.scale"`, f64, one per block
  (`[n_blocks]`). That is what tula's helpers read and `tula_find_scale` finds,
  with `need = tula_int4_blocks(nelems, block)`. The codec doesn't interpret
  the pairing, so an importer may keep its source's scale dtype under its own
  convention, as ADR 0002 allows. `tula_find_scale` finds only f64 sidecars.
- **Helpers** (pure, like NF4's), with `TULA_INT4_BLOCK = 32` (Q4_0's block):
  - `tula_int4_bytes(n)`, `tula_int4_blocks(n, block)`, `tula_int4_get(codes, i)`;
  - `tula_int4_pack(src_f64, n, block, scales, codes)`, which is **Q4_0's
    reference rule in f64**. `m` is the block's value of largest magnitude (the
    first, on a tie) and `d = m / −8`. Each code is `x / d` rounded half up and
    clamped to −8..7. So `m` itself is −8, `d` is negative when `m` is
    positive, and an all-zero block gets `d = +0` and codes 0;
  - `tula_int4_unpack(codes, scales, n, block, dst_f64)`: `value = code × d`.
- **Importing Q4_0 losslessly** takes three steps: each code is `q − 8` (as a
  nibble, `q XOR 8`); the elements move from GGUF's block layout (byte `j` of a
  block holds elements `j` and `j + 16`) to element order; and each block's f16
  `d` becomes the scale, widened exactly to f64 for tula's helpers, or kept as
  F16 under the importer's convention.

## Consequences

- **Positive** — 4-bit weights are stored at half a byte per element, with the
  same sidecar convention as NF4 and int8. The scales stay ordinary tensors,
  visible to every accessor, and `tula_find_scale`, the index and the existing
  guards apply unchanged. Every nibble is a valid code, so the only value rule
  is the unused nibble's.
- **Negative** — INT4 plus a scale is symmetric only. Q4_1 (`q × d + m`) and
  asymmetric AWQ/GPTQ don't fit without a second sidecar (a `.min` or zero
  point) and, to stay lossless, unsigned codes. Those are deferred; GPTQ/AWQ
  already have a lossless path through I32. GGUF's K-quants (two-level scales)
  stay out too: they need an opaque block dtype or dequantization.
- **Neutral** —
  - A 1.2–1.7 strict validator returns `TULA_ERR_DTYPE` for INT4; its plain
    reader opens, verifies and resolves the file as before.
  - Ternary's and NF4's unused bits stay unchecked, because rejecting them now
    would change verdicts 1.2–1.7 gave. INT4 is checked from the start.
  - An unsigned 4-bit dtype, for the asymmetric schemes, is a later MINOR if
    an importer needs one.

## Alternatives considered

- **GGUF-compatible blocks with an inline f16 scale**: rejected. tula would own a
  container inside a container, and the scales would be opaque bytes again
  (ADR 0002 rejected exactly that). "Compatible" would also mean adopting all of
  GGUF's block layout: the split nibble order, unsigned codes with an offset of 8,
  and then one dtype per GGUF block type. An importer converts once instead.
- **Unsigned codes (0..15, offset 8) for INT4**: rejected for a symmetric type.
  `value = code × scale` is what a signed code means, and Q4_0's offset is a
  storage detail of its format.
- **`d = absmax / 7`** (the int8 helper's style): rejected. It never uses code −8,
  wasting one of 16 levels. Q4_0's rule uses all 16, and matching it means
  tula's output resembles what llama.cpp writes from the same values.
- **f16 scales by default**: rejected. tula's helpers and `tula_find_scale` use f64
  sidecars (ADR 0002, NF4), and f64 holds any source scale exactly.
- **Strict checking that a `.scale` fits its tensor** (also asked by the
  importer): rejected. ADR 0002 leaves the pairing to the consumer, and
  `tula_find_scale` already checks that a sidecar is large enough for the
  unpack the caller is about to do.
