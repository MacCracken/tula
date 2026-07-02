# tula — API Reference

The public surface of the tula codec. Consumers pull `dist/tula.cyr` via a
`[deps.tula]` entry and supply their own `sigil` (the bundle leaves `ed25519_*`
unresolved — the standard consumer-bundle pattern). This document is the **frozen
v1.0 surface**; stability guarantees are in [`STABILITY.md`](../STABILITY.md).

Conventions: all values are `i64`. Pointers are raw addresses. `f64` values are
IEEE-754 **bit patterns** carried in an `i64` (the sovereign convention) — build
them with the `f64_*` builtins. Buffers are caller-allocated unless noted.

---

## On-disk format (v1)

All fields are i64-aligned little-endian. `TULA_MAGIC = 0x54554C41` ("TULA"),
`TULA_VERSION = 1`.

```
HEADER (64 B)                       ENTRY (144 B), × count at manifest_off
  +0  magic                           +0   name[48]  (cstring, NUL-padded, ≤47)
  +8  version                         +48  dtype     (TulaDType)
  +16 tensor_count                    +56  ndim      (0..8)
  +24 manifest_off (= 64)             +64  shape[8]  (i64 × 8; unused dims 0)
  +32 payload_off                     +128 data_off  (offset within payload)
  +40 payload_len                     +136 data_len  (bytes)
  +48 sig_off  (0 = unsigned)
  +56 sig_len  (0 = unsigned, else 64)

PAYLOAD at payload_off; each tensor 8-byte aligned.
SIGNATURE (Ed25519, 64 B) at sig_off = payload_off + payload_len, covering [0, sig_off).
```

`payload_off == 64 + count * 144`. `data_off + data_len ≤ payload_len`.

### dtypes (`TulaDType`)

| Const | Val | Payload |
|---|---|---|
| `TULA_DT_F64`     | 0 | raw f64 (i64 bit patterns), `data_len = nelems*8` |
| `TULA_DT_INT8`    | 1 | int8 (two's-complement bytes), `data_len = nelems` |
| `TULA_DT_TERNARY` | 2 | 2-bit packed {−1,0,+1}, `data_len = ceil(nelems/4)` |
| `TULA_DT_NF4`     | 3 | 4-bit NF4 codes, `data_len = ceil(nelems/2)` |

Quantized dtypes store their scale(s) as a **sidecar** `f64` tensor named
`"<name>.scale"` (ADR 0002) — the codec never interprets it.

---

## Errors — `src/error.cyr`

`fn tula_err_name(code) -> cstring` — human name for a `TulaErrCode` (never null).

| Code | Val | | Code | Val |
|---|---|---|---|---|
| `TULA_OK` | 0 | | `TULA_ERR_UNSIGNED` | 7 |
| `TULA_ERR_MAGIC` | 1 | | `TULA_ERR_SIG` | 8 |
| `TULA_ERR_VERSION` | 2 | | `TULA_ERR_BOUNDS` | 9 |
| `TULA_ERR_TRUNCATED` | 3 | | `TULA_ERR_NDIM` | 10 |
| `TULA_ERR_TOO_MANY` | 4 | | `TULA_ERR_HEADER` | 11 |
| `TULA_ERR_NAME_LONG` | 5 | | `TULA_ERR_TOO_BIG` | 12 |
| `TULA_ERR_OOM` | 6 | | `TULA_ERR_OTHER` | 99 |

---

## Builder (write) — `src/format.cyr`

- `fn tula_builder_new() -> b` — allocate a builder (cap `TULA_BUILDER_MAX = 256`
  tensors).
- `fn tula_builder_add(b, name, dtype, shape, ndim, data, data_len) -> 0 |
  TULA_ERR_TOO_MANY` — append a tensor. `name` cstring (≤47 chars, truncated
  otherwise), `shape` an `i64[ndim]` array, `data`/`data_len` the raw payload
  bytes (already packed for quantized dtypes). Pointers are borrowed until
  `finish`.
- `fn tula_builder_finish(b) -> buf` — serialize to one contiguous **unsigned**
  buffer. Use `tula_total_len(buf)` for its length.
- `fn tula_builder_finish_signed(b, sk) -> buf` — serialize and append an Ed25519
  signature over `[0, sig_off)`. `sk` is a 64-byte secret key (`seed‖pk`, from
  `ed25519_keypair`).

*Low-level*: `tula_serialize(b, sig_len)` (0 or 64) underlies both; call the
`finish` wrappers.

## Reader — `src/format.cyr`

- `fn tula_validate(buf, len) -> TULA_OK | TULA_ERR_*` — **the untrusted-input
  gate.** Full structural validation against `len`, overflow-safe. Structure
  only; not authenticity.
- `fn tula_open(buf, len) -> r | 0` — validate then return the buffer as a reader
  handle (`0` on any breach). **All untrusted input must pass through here** (or
  `tula_validate`) before the accessors below.
- `fn tula_count(r) -> n` · `fn tula_format_version(r) -> v` · `fn
  tula_total_len(buf) -> bytes`.
- `fn tula_entry(r, i) -> e` — pointer to manifest entry `i` (`0 ≤ i < count`).
- `fn tula_entry_name(e) -> cstring` · `tula_entry_dtype(e)` ·
  `tula_entry_ndim(e)` · `tula_entry_dim(e, k)` · `tula_entry_data_len(e)`.
- `fn tula_entry_data(r, e) -> ptr` — pointer to the tensor's payload bytes.
- `fn tula_find(r, name) -> e | 0` — first entry with that name.
- `fn tula_is_signed(r) -> 0 | 64` — signature **presence** (length), not validity.

The reader is zero-copy over `buf`; accessors return pointers *into* it.

## Signature — `src/sign.cyr`

- `fn tula_verify(r, pk) -> TulaSigStatus` — `TULA_SIG_UNSIGNED` (0) /
  `TULA_SIG_OK` (1) / `TULA_SIG_BAD` (2). `pk` is a 32-byte Ed25519 public key.
  Requires a buffer that passed `tula_open`/`tula_validate`.

Crypto is `sigil`'s; keys are the caller's (tula owns no key management).

## File I/O — `src/fileio.cyr`

- `fn tula_write_file(path, buf, len) -> bytes_written | <0` — create/truncate,
  write the serialized buffer.
- `fn tula_read_file(path) -> r | 0` — read into a fresh heap buffer, bomb-guard
  the header total, then `tula_open` (full validation).
- `fn tula_open_mmap(path) -> r | 0` — zero-copy read-only mmap (bomb-guarded +
  validated). Release with `fn tula_close_mmap(r)`.

tula files are self-describing (the header carries the total length), so reads
need no `stat()`.

## dtype payload helpers — `src/dtype.cyr`

Pure, caller-driven transforms — they never touch the file layout. **Before
unpacking a foreign tensor, call `tula_entry_payload_ok(e)` first** (see below).

**Ternary** ({−1,0,+1} as i64 slots ↔ 2-bit codes, 4/byte):
- `fn tula_ternary_bytes(n) -> ceil(n/4)`
- `fn tula_ternary_pack(src_i64, n, dst) -> packed_len`
- `fn tula_ternary_unpack(src, n, dst_i64) -> n`
- `fn tula_ternary_get(packed, i) -> -1 | 0 | +1`

**int8** (per-tensor absmax):
- `fn tula_int8_quant(src_f64, n, dst_i8) -> scale` (f64 bits; store as sidecar)
- `fn tula_int8_dequant(src_i8, n, scale, dst_f64) -> 0`

**NF4** (4-bit blockwise NormalFloat, QLoRA codebook):
- `fn tula_nf4_blocks(n, block) -> ceil(n/block)` · `fn tula_nf4_bytes(n) ->
  ceil(n/2)`
- `fn tula_nf4_pack(src_f64, n, block, scales_f64, nibbles) -> n_blocks` — writes
  per-block absmax into `scales` (store as sidecar) and 4-bit codes into
  `nibbles`.
- `fn tula_nf4_unpack(nibbles, scales, n, block, dst_f64) -> n`
- `fn tula_nf4_get(nibbles, i) -> code 0..15` · `fn tula_nf4_level(i) -> f64` (the
  codebook). `TULA_NF4_BLOCK = 64` (typical block size).

**Payload-length guard** (untrusted-input discipline):
- `fn tula_packed_len(dtype, nelems) -> bytes | -1` — expected packed byte length.
- `fn tula_entry_payload_ok(e) -> 1 | 0` — overflow-safe check that an entry's
  `data_len` is large enough for its dtype+shape. **Run it before any unpack on a
  foreign entry** (a lying `shape` could otherwise drive an over-read).

Double-quant composes: int8-quantize a `"<name>.scale"` tensor and store its own
`"<name>.scale.scale"` — the same convention, one level down.

---

## Minimal consumer flow

```
# write
b = tula_builder_new()
tula_builder_add(b, "w", TULA_DT_F64, shape, ndim, data, len)
buf = tula_builder_finish_signed(b, sk)
tula_write_file("model.tula", buf, tula_total_len(buf))

# read (untrusted)
r = tula_read_file("model.tula")        # 0 if malformed
if (r == 0) { ...reject... }
if (tula_verify(r, pk) != TULA_SIG_OK) { ...reject... }
e = tula_find(r, "w")
if (tula_entry_payload_ok(e) == 0) { ...reject... }
p = tula_entry_data(r, e)               # in-bounds, zero-copy
```

A complete runnable example is in [`examples/consumer.cyr`](../examples/consumer.cyr).
