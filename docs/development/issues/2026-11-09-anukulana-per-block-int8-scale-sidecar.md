# anukulana stores packed Q8_0 as INT8 codes plus an F16 per-block `.scale` sidecar (since 1.6.1): a use of ADR 0002 beyond its examples, and an input for the 1.8 int4 ADR

**Status:** 🔴 **OPEN.** For information, plus a request for the 1.8.x int4 ADR. Nothing in tula is
broken.
**Placement:** 1.8.x (the int4 ADR); a note on ADR 0002 at tula's convenience.
**Discovered:** 2026-11-09, by anukulana 1.6.1, which writes these files.
**Severity:** None today. It matters once a second consumer reads anukulana's files, or once tula fixes
its int4 layout.
**Affects:** tula 1.6.1 (format v1). Files written by anukulana `convert` from a Q8_0 GGUF.

## Summary

ADR 0002 makes quantization scales sidecar tensors named `<w>.scale`, and leaves the
`w` ↔ `w.scale` relationship as a consumer convention. Its examples are an int8 `w` with an
f64 `[1]` or f64 `[rows]` scale, and an NF4 `w` with a per-block f64 scale. anukulana 1.6.1 now
writes a third shape of it.

**The convention.** For an INT8 tensor `w` in HF's layout, 1-D or 2-D:

- **`w.scale`** is **F16** (tula 1.3.0's dtype), holding llama.cpp's Q8_0 block scales exactly as
  the GGUF stores them.
- **One scale per 32 consecutive codes along one axis.** The sidecar's shape names the axis:
  - `[d0/32, d1]`: blocks run down dim 0 (a Conv1D weight transposed back from ggml's `[out, in]`);
  - `[d0, d1/32]`: blocks run along dim 1 (an embedding);
  - `[d0/32]`: a vector.

  For a 2-D tensor the two shapes can't coincide.
- **Value = code × scale**, with the code read as int8 and the scale widened from f16. That is
  ggml's Q8_0 dequantization, so the file is lossless against the GGUF it came from.

anukulana records the packed types in the metadata as `anukulana.packed = Q8_0`. Its reader refuses an
INT8 tensor without a valid sidecar: none, a non-F16 one, or one of neither shape.

**Evidence.** A real Q8_0 GPT-2 small converts to a 134.9 MB signed tula file (497.8 MB when the same
weights are written as F32). It loads bit-identical to anukulana's import of the GGUF, and that import
equals ggml's own dequantization with 0 of 124,439,808 params differing. The tests are
`tests/tcyr/convert.tcyr` in anukulana (`test_packed_q8_convention`, `test_q8_pack_orders`); the
convention is written up in its `docs/api.md`, section Convert.

## Ask

1. **Record it, or tell anukulana what to change.** Either a short note on ADR 0002, saying that F16
   scales and per-block scales along a named axis are a valid use of `w.scale`, or a different
   shape or dtype that tula prefers. Few files exist yet, so changing it now is cheap.
2. **For the 1.8 int4 ADR, here is what anukulana would write next.** The other llama.cpp block
   types are written as exact F32 today, because tula has no 4-bit dtype. With int4, anukulana would
   keep them packed the same way:
   - **Q4_0:** int4 codes plus an F16 `.scale` per 32 codes, the same layout as above. Symmetric:
     `(q − 8) × d`.
   - **Q4_1** (and Q5_1): it also needs a per-block **minimum** (`q × d + m`). A sibling sidecar,
     for example `w.min`, would keep the sidecar pattern; inline scales would need a block layout
     that includes `m`.
   - **The K-quants** (Q2_K … Q6_K) use two-level scales: a superblock `d` / `dmin` over 6-bit
     sub-block scales and mins. Those probably stay dequantized, or would need an opaque
     "ggml block" dtype; that is tula's call, and anukulana does not need it.

   anukulana would prefer the sidecar option tula's roadmap already lists for that ADR ("codes plus
   an ADR 0002 `.scale` sidecar"), because it matches the INT8 case above.
3. **Optional:** tula could check the pairing in its strict validator (a `.scale` whose shape fits its
   tensor). anukulana checks it on read either way, so this is defense in depth for other readers.
