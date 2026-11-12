# 0009 — Integer and boolean dtypes: I16, I32, I64, U8 and BOOL, stored raw

**Status**: Accepted
**Date**: 2026-11-12

## Context

A real checkpoint holds more than weights. Each of these is common:

- **GPTQ and AWQ imports** pack 4-bit codes into `int32` tensors (`qweight`,
  `qzeros`) and keep a per-column group index (`g_idx`, `int32`).
- **Position and token-type buffers** (BERT's `position_ids`, and many
  encoder models) are `int64`.
- **Masks and causal-attention buffers** are `bool`.
- **Byte tensors** (`uint8`) carry packed state, such as bitsandbytes'
  serialized quantization state and image tokenizers' code tables.
- `int16` is rarer (audio codecs, some quantizers), but safetensors and GGUF
  both define it.

tula's dtypes were f64, the three quantized codes (int8, ternary, NF4) and
F32/F16/BF16 (ADR 0005). An importer could store these tensors only by
reinterpreting them, for example as int8 bytes under a shape that isn't the
real one. That loses the tensor's type and fails `tula_validate_strict`'s
shape rule. Converting them to f64 isn't lossless either: an `int64` above
2⁵³ doesn't survive.

New `TULA_DT_*` values are additive (a MINOR, STABILITY.md). `tula_validate`
accepts unknown dtypes in every 1.x, so older plain readers still open such
files, and 1.2+'s strict validator rejects what it doesn't know, as it did for
ADR 0005's floats.

## Decision

**Add five dtypes, stored as raw little-endian values:**

| Constant | Code | Element | Width |
|---|---:|---|---:|
| `TULA_DT_I16` | 7 | two's-complement signed 16-bit | 2 |
| `TULA_DT_I32` | 8 | two's-complement signed 32-bit | 4 |
| `TULA_DT_I64` | 9 | two's-complement signed 64-bit | 8 |
| `TULA_DT_U8` | 10 | unsigned 8-bit | 1 |
| `TULA_DT_BOOL` | 11 | one byte: 0 is false, 1 is true | 1 |

- **Storage.** `data_len = nelems × width`, with no header, scale or padding
  inside the payload. Little-endian, as every other tula field is, and as every
  cyrius target lays out memory.
- **Signed 8-bit is `TULA_DT_INT8`** (code 1). Its bytes are already a
  two's-complement int8 tensor; tula's int8 helpers read them as quantized codes,
  but the dtype doesn't require that. An importer maps safetensors' `I8` to it.
- **Sizes everywhere.** `tula_packed_len` gives the widths, so
  `tula_entry_payload_ok` guards the new dtypes and `tula_validate_strict`
  requires `data_len` to match the shape exactly, as for every other dtype.
- **BOOL is canonical in strict.** `tula_validate_strict` rejects a BOOL tensor
  holding any byte other than 0 or 1, with a new code, **`TULA_ERR_VALUE` (19)**:
  a payload value its dtype doesn't allow. This is the first strict rule that
  reads tensor values (before, strict read only padding, names and metadata). It
  costs one 64-bit compare per 8 elements. A file is either canonical or
  rejected: a byte of 2 reads as true in C and NumPy, but is undefined in Rust,
  and two readers shouldn't disagree about a mask.
- **No conversion helpers.** The values are what the consumer's own loads
  return, so there is nothing to convert. A consumer reads element `i` with
  `load8` / `load16` / `load32` / `load64` at `p + i × width`. In cyrius
  those loads zero-extend and `>>` is a logical shift, so I16 and I32 are
  sign-extended by subtraction: `v - ((v & 0x8000) << 1)` and
  `v - ((v & 0x80000000) << 1)`. `docs/api.md` shows this.
- **The checked add is unchanged.** It never reads payloads. Its promise, that a
  builder fed only through it gives a file strict accepts, already depends on
  each `data_len` being the packed length. It now also depends on each BOOL
  payload holding only 0 and 1.

## Consequences

- **Positive** — an importer can store a checkpoint's ids, masks, buffers and
  packed integer codes losslessly and under their own types. GPTQ/AWQ imports
  keep their int32 tensors as they are. The existing guards (`payload_ok`, strict
  sizes, the fuzzer's consumer discipline) cover the new dtypes with no new
  mechanism. Files that don't use them are byte-for-byte what 1.6 wrote.
- **Negative** — strict now reads every BOOL payload. That's linear in the mask
  size (masks are small next to weights; see `docs/benchmarks.md`). A consumer
  has to sign-extend I16/I32 itself.
- **Neutral** —
  - A 1.6 consumer that runs `tula_validate_strict` on a file with these
    dtypes gets `TULA_ERR_DTYPE` until it upgrades. Its `tula_open`, verify,
    names, metadata and index work as before, and `tula_entry_payload_ok`
    returns 1 (no contract for a dtype it doesn't know).
  - Codes 7–11 were unknown before 1.7: tula never wrote them, and strict
    rejected them. A file that used them privately now reads as these dtypes.
  - Ternary's unused 2-bit code (3) stays unchecked. Rejecting it now would
    change a strict verdict 1.2–1.6 gave, which STABILITY.md rules out.
  - The 1.8 FP8 and int4 dtypes take codes from 12 on.

## Alternatives considered

- **Bits for BOOL** (8 per byte): rejected. PyTorch, NumPy and safetensors all
  store one byte per bool, so an importer would have to repack, the size would no
  longer be `nelems × width`, and tula would need pack/unpack helpers for a
  dtype that is rarely large.
- **Accept any nonzero BOOL byte as true**: rejected. Strict promises a
  canonical file, so one mask has one encoding.
- **U16, U32, U64**: left out. The checkpoints tula targets don't carry them
  (PyTorch only recently gained them, with limited support). A later MINOR adds
  them, with codes after 1.8's, when an importer needs one.
- **A separate code for I8**: rejected. INT8's bytes are I8's, and two codes for
  the same bytes would give one tensor two canonical forms.
- **Element-read helpers** (`tula_i32_at(p, i)` and the like): not now. The
  roadmap scoped 1.7 to sizes, each read is one load and, for I16/I32, one
  subtraction, and a consumer knows its dtype. If consumers keep getting sign
  extension wrong, a MINOR can add them.
- **Converting integers to f64 on import**: rejected, as above: it isn't lossless
  for int64, it doubles small integer tensors, and it isn't the codec's job
  (ADR 0001).
