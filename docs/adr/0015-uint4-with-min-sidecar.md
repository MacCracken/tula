# 0015 — UINT4: unsigned 4-bit codes, with a `.min` sidecar beside `.scale`

**Status**: Accepted
**Date**: 2026-11-12

## Context

ADR 0011 added `TULA_DT_INT4`, signed codes with one scale per block:
`value = code × scale`. That fits symmetric 4-bit (llama.cpp's Q4_0). It
deferred the asymmetric schemes, which add a per-block offset:

- **GGUF Q4_1**: blocks of 32, each with an f16 scale `d` and an f16 minimum
  `m`, and unsigned codes `q` of 0..15. Then `value = q × d + m`. Its reference
  quantizer takes `m` as the block's smallest value and `d = (max − min) / 15`.
- **AWQ / GPTQ with zero points**: `value = (q − z) × s`, with an integer zero
  point `z` per group. These already import losslessly as `TULA_DT_I32`
  (ADR 0009).

The Type-3 importer (anukulana) reads Q4_1 today, and writes it to tula as
exact F32, four times the bytes. Its open issue
(`2026-11-09-anukulana-per-block-int8-scale-sidecar.md`, in its repo) asks, for
Q4_1, for "a per-block minimum … a sibling sidecar, for example `w.min`", to
match how it stores Q8_0 with a `.scale`.

Two choices follow:
- whether the codes are a new unsigned dtype, or INT4 with an offset;
- how a sidecar other than `.scale` is found.

## Decision

**Add `TULA_DT_UINT4 = 15`: unsigned 4-bit codes, 0..15, in INT4's layout.
Blockwise scales go in `"<name>.scale"` and blockwise minimums in
`"<name>.min"`, both ADR 0002 sidecars. `value = code × scale + min`.**

- **Storage.** It is INT4's layout exactly:
  - two codes per byte, element 2k in the low nibble of byte k;
  - `data_len = ceil(nelems / 2)` (`tula_int4_bytes`);
  - an odd count's last high nibble is zero, which `tula_validate_strict`
    checks (`TULA_ERR_VALUE`, 19).

  Only the meaning of a code differs: 0..15, with no sign.
- **Sidecars**, both f64, one per block (`tula_int4_blocks(nelems, block)` of
  them):
  - `"<name>.scale"`, the step `d`;
  - `"<name>.min"`, the offset `m`.

  The codec doesn't interpret the pairing (ADR 0002). An importer may keep its
  source's scale dtype under its own convention; tula's helpers and lookups use
  f64.
- **Helpers:**
  - `tula_uint4_get(codes, i)`;
  - `tula_uint4_pack(src, n, block, scales, mins, codes)`, Q4_1's reference
    rule in f64: `m` is the block's smallest value and `d = (max − min) / 15`.
    Each code is `(x − m) / d` rounded half up and clamped to 0..15, so `m`
    gets 0 and the largest value 15. A block of equal values gets `d = +0` and
    codes 0. The step divides, as `tula_int4_pack` does; llama.cpp multiplies by
    `1 / d`, which can round a code differently, and the stored `d` and `m` are
    exact either way.
  - `tula_uint4_unpack(codes, scales, mins, n, block, dst)`: each value is
    `f64_mul(code, d)` then `f64_add(·, m)`, two IEEE operations with no fused
    multiply-add. From a block of 16 the block's 16 values are made once.
- **Finding a sidecar by its suffix**, any suffix:
  - `tula_find_sidecar(r, e, suffix, need)`;
  - `tula_index_find_sidecar(ix, e, suffix, need)`;
  - `tula_set_find_sidecar(set, e, suffix, need)`.

  Each finds `"<full name><suffix>"` as an f64 tensor with at least `need`
  elements, as the `.scale` lookups do (they are now this lookup with
  `".scale"`). `.min` doesn't need a function of its own, and a later
  convention (`.zero`) won't either.
- **Importing Q4_1 losslessly**, as ADR 0011 gives for Q4_0:
  - move the codes from the block layout (byte `j` holds elements `j` and
    `j + 16`) into element order, with no XOR, since Q4_1's codes are already
    unsigned;
  - widen each block's f16 `d` to `.scale` and f16 `m` to `.min`, exactly.

  The stored file is exact. A value tula's unpack gives is the f64 of
  `q × d + m`, which can differ in the last bits from llama.cpp's f32
  arithmetic.
- **`tula_unpack_par` doesn't cover UINT4**, which needs two sidecars, and
  returns −1 for it. A parallel form is a throughput follow-up (roadmap 1.13.x)
  for when a consumer needs one.

## Consequences

- **Positive**
  - Q4_1 checkpoints are stored at half a byte per weight, losslessly. The
    importer writes four times fewer bytes than its F32 fallback.
  - The sidecar pattern stays the one convention (ADR 0002): `.scale`, now
    `.min`, found by one lookup.
  - Strict's only value rule is the unused nibble's, as for INT4.
- **Negative**
  - **A second 4-bit dtype.** INT4 with a `.min` would have covered Q4_1's
    values, but not its codes: Q4_1's code 0 is the minimum, and a signed code
    would need an offset of 8 baked into every reader.
  - **No `tula_unpack_par` for UINT4 yet.**
- **Neutral**
  - **AWQ/GPTQ zero points** (`(q − z) × s`) can't be expressed exactly as a
    `.min`, because `q × s − z × s` rounds differently. A `.zero` sidecar of
    integer zero points, found with the same lookup, is a later MINOR if an
    importer wants them unpacked; they import losslessly as `I32` today.
  - **Q5_0 / Q5_1** need 5-bit codes, a dtype of their own, if an importer asks.
  - **A 1.11 reader** opens a UINT4 file, verifies it and finds its sidecars by
    name; its strict validator returns `TULA_ERR_DTYPE`.

## Alternatives considered

- **INT4 plus `.min`:** rejected, as above. The codes would carry Q4_1's values
  minus 8, and reading them back needs that offset.
- **One sidecar holding both `d` and `m`** (a `[n_blocks, 2]` tensor): rejected.
  It breaks the one-scale-per-block shape every `.scale` reader expects, and an
  importer whose scales are F16 couldn't keep that convention for one array and
  not the other.
- **A `tula_find_min` and its index and set forms:** rejected for one lookup
  by suffix, which `.scale`, `.min` and any later sidecar share.
- **Q4_1's reciprocal multiply** (`(x − m) × (1/d)`): rejected, for the same
  reason ADR 0011 gives. tula's pack is a quantizer for f64 data, and the stored
  scales are what make an import exact.
