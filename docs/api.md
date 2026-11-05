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
| `TULA_DT_F32`     | 4 | IEEE binary32, LE, `data_len = nelems*4` *(1.3.0)* |
| `TULA_DT_F16`     | 5 | IEEE binary16, LE, `data_len = nelems*2` *(1.3.0)* |
| `TULA_DT_BF16`    | 6 | bfloat16 (binary32's top half), LE, `data_len = nelems*2` *(1.3.0)* |

Quantized dtypes store their scale(s) as a **sidecar** `f64` tensor named
`"<name>.scale"` (ADR 0002) — the codec never interprets it.

### Long names (1.3.0, ADR 0004)

A tensor name over 47 bytes doesn't fit the 48-byte field. Its entry stores a
47-byte **key** instead: the name's first 30 bytes, `~`, then 16 lowercase hex
digits of FNV-1a-64 of the name. The full names live in the **names table**, a
reserved int8 tensor `__tula.names__` that is always the last entry. Its payload
is the magic `"tula.nm1"`, a record count L, L records `{entry_index, name_off,
name_len}` (i64 each, sorted by entry), then the names, each NUL-terminated.
Files without long names have no table. Every 1.x reader opens files that have
one, seeing the keys as names and the table as an ordinary int8 tensor.

### File metadata (1.6.0, ADR 0008)

Key/value text about the file (architecture, config, provenance) lives in the
**metadata table**, a reserved int8 tensor `__tula.meta__`. It sits after every
ordinary tensor and before the names table, which stays last, and the signature
covers it. Its payload is the magic `"tula.mt1"`, a pair count P, then P records
`{key_off, key_len, val_off, val_len}` sorted by key (unique), then for each
record the key, a NUL, the value and a NUL. Keys are 1–255 ASCII letters,
digits, `.`, `_` or `-`, starting with a letter; `tula.*` is reserved. Values
are well-formed UTF-8 text, no NUL, ≤ 16 MiB. A table holds ≤ 4,096 pairs and
≤ 64 MiB. Every 1.x reader opens such files and sees an ordinary int8 tensor.

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
| `TULA_ERR_OOM` | 6 | | `TULA_ERR_DUP_NAME` | 13 |
| | | | `TULA_ERR_LAYOUT` | 14 |
| | | | `TULA_ERR_SHAPE` | 15 |
| | | | `TULA_ERR_DTYPE` | 16 |
| | | | `TULA_ERR_NAMES` | 17 |
| | | | `TULA_ERR_META` | 18 |
| | | | `TULA_ERR_OTHER` | 99 |

Codes 13–16 are new in 1.2.0, returned by the checked add and the strict
validator. 17 is new in 1.3.0 (a malformed names table, from the strict
validator). 18 is new in 1.6.0 (a bad metadata key or value from the writer, or
a malformed metadata table from the strict validator).

---

## Builder (write) — `src/format.cyr`

- `fn tula_builder_new() -> b | 0` — allocate a builder (cap `TULA_BUILDER_MAX =
  256` tensors).
- `fn tula_builder_new_cap(max) -> b | 0` *(1.2.0)* — a builder for up to `max`
  tensors, `1 ≤ max ≤ TULA_READ_MAX_TENSORS` (0 otherwise or on allocation
  failure). Real checkpoints pass 256: Llama-2-7B has 291 tensors.
- `fn tula_builder_add(b, name, dtype, shape, ndim, data, data_len) -> 0 |
  TULA_ERR_*` — append a tensor. `name` cstring (≤47 chars, truncated
  otherwise — two long names can truncate to the same stored name, see
  `SECURITY.md`), `shape` an `i64[ndim]` array, `data`/`data_len` the raw payload
  bytes (already packed for quantized dtypes). The name and shape are **copied
  at add** (1.2.0; before, they were borrowed until `finish`, so reusing one
  shape buffer gave every tensor the last shape); `data` is borrowed until
  `finish`. Errors, each leaving the builder unchanged: `TULA_ERR_TOO_MANY`
  (the builder's cap reached), `TULA_ERR_NDIM` (`ndim` outside 0..8),
  `TULA_ERR_BOUNDS` (`data_len < 0`), `TULA_ERR_TOO_BIG` (the payload would pass
  `TULA_READ_MAX_BYTES`). *1.1.2: the last three were accepted before and wrote
  a corrupt or unreadable file.*
- `fn tula_builder_add_checked(b, name, dtype, shape, ndim, data, data_len) -> 0 |
  TULA_ERR_*` *(1.2.0)* — `tula_builder_add`, also refusing a name over 47 chars
  (`TULA_ERR_NAME_LONG`, instead of truncating it) and a name the builder already
  holds, from either kind of add (`TULA_ERR_DUP_NAME`). The check is O(1) per
  add, through a name index. A builder fed only through this, with each
  `data_len` equal to `tula_packed_len(dtype, nelems)`, writes files
  `tula_validate_strict` accepts.
- `fn tula_builder_add_long(b, name, dtype, shape, ndim, data, data_len) -> 0 |
  TULA_ERR_*` *(1.3.0)* — names of **any length**. A name of 47 chars or fewer
  is added exactly as `tula_builder_add_checked` adds it. A longer name is
  stored whole in the names table, which `finish` appends after every other
  tensor, and its entry holds the key. Errors are those of `add_checked` except
  `TULA_ERR_NAME_LONG`, plus `TULA_ERR_DUP_NAME` for the name `__tula.names__`
  itself, or for a first long name when the builder already holds a tensor of
  that name, and `TULA_ERR_OOM` if the name copy fails. Duplicates are checked
  on keys: two different long names refuse each other only if both their 30-byte
  prefix and their 64-bit hash match. That is loud, never a silent collision.
  Once a builder holds a long name, `add_checked` also refuses `__tula.names__`.
- `fn tula_builder_set_meta(b, key, value) -> 0 | TULA_ERR_*` *(1.6.0, ADR
  0008)* — set or replace a metadata pair. Both strings are copied, and the
  table is written in key order, so the same pairs give the same bytes whatever
  order they were set in. tula writes no keys of its own. Errors (builder
  unchanged):
  - `TULA_ERR_META`: a bad key, the reserved `tula.` prefix, a value that isn't
    UTF-8 or is over 16 MiB, or past 4,096 pairs or 64 MiB;
  - `TULA_ERR_DUP_NAME`: the first pair, when the builder already holds a tensor
    named `__tula.meta__`;
  - `TULA_ERR_TOO_MANY` / `TULA_ERR_TOO_BIG`: no manifest slot, or the file cap;
  - `TULA_ERR_OOM`.

  Once metadata is set, `add_checked` refuses `__tula.meta__`; `add_long`
  always does.
- `fn tula_builder_finish(b) -> buf | 0` — serialize to one contiguous
  **unsigned** buffer (0 if the allocation fails). Use `tula_total_len(buf)` for
  its length. Every byte is written (alignment padding is zero), so the same
  builder always gives the same bytes. The whole file is one allocation, so the
  stdlib's per-allocation cap (2 GiB) bounds what can be written today.
- `fn tula_builder_finish_signed(b, sk) -> buf | 0` — serialize and append an
  Ed25519 signature over `[0, sig_off)`. `sk` is a 64-byte secret key
  (`seed‖pk`, from `ed25519_keypair`).

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
- `fn tula_find(r, name) -> e | 0` — first entry with that name (exact match; a
  query over 47 chars never matches, since no stored name is that long).
- `fn tula_is_signed(r) -> 0 | 64` — signature **presence** (length), not validity.
- `fn tula_find_name(r, name) -> e | 0` *(1.3.0, `src/names.cyr`)* — find by
  **full** name, any length. A name of 47 chars or fewer is matched in place
  (never against a long-named entry's key); a longer one through its key,
  accepted only if the names table confirms the full name. A hash collision can't
  return the wrong tensor.
- `fn tula_entry_full_name(r, e) -> cstring` *(1.3.0)* — the full name: a pointer
  into the names table for a long-named entry, else `tula_entry_name(e)`. Each
  record is bounds-checked when read; one that doesn't hold up is treated as
  absent, and the key comes back.
- `fn tula_has_long_names(r) -> 1 | 0` *(1.3.0)* — whether a names table is present.
- `fn tula_entry_nelems(e) -> n | -1` *(1.2.0, `src/dtype.cyr`)* — element count:
  the product of the dims, so 1 for a 0-dim entry (a scalar) and 0 for an empty
  tensor. −1 for a negative dim or a product over `TULA_READ_MAX_BYTES`
  (overflow-safe).

The reader is zero-copy over `buf`; accessors return pointers *into* it.

## Signature — `src/sign.cyr`

- `fn tula_verify(r, pk) -> TulaSigStatus` — `TULA_SIG_UNSIGNED` (0) /
  `TULA_SIG_OK` (1) / `TULA_SIG_BAD` (2). `pk` is a 32-byte Ed25519 public key.
  Requires a buffer that passed `tula_open`/`tula_validate`.
- `fn tula_verify_required(r, pk) -> TULA_OK | TULA_ERR_UNSIGNED | TULA_ERR_SIG`
  *(1.2.0)* — the same check for a consumer that requires a signature. A stripped
  signature leaves a valid *unsigned* file, which this rejects as firmly as a bad
  one.

Crypto is `sigil`'s; keys are the caller's (tula owns no key management).

## File I/O — `src/fileio.cyr`

- `fn tula_write_file(path, buf, len) -> bytes_written | <0` — create/truncate,
  write the serialized buffer. Not crash-safe: a failure leaves a truncated file,
  which the readers then reject.
- `fn tula_write_file_atomic(path, buf, len) -> len | <0` *(1.4.0)* — crash-safe:
  the bytes go to a unique sibling temp file, which is fsync'd and renamed over
  `path` (the stdlib's `file_write_atomic`). On failure `path` is untouched.
- `fn tula_builder_write_file(b, path) -> file_len | <0` *(1.4.0, ADR 0006)* —
  **stream** the builder's file to disk: exactly the bytes `tula_builder_finish(b)`
  returns, never held in memory, so there is no 2 GiB cap. The header, manifest
  and names table go through a 64 KiB staging buffer; each payload is written
  straight from the caller's buffer. Atomic: a random `O_EXCL` sibling temp
  `<path>.tula-<16 hex>.tmp` with the target's mode, written, fsync'd, renamed
  over `path`, then the directory fsync'd. On any failure the temp is removed and
  `path` is untouched. A symlink at `path` is replaced, not written through.
  Returns the file's length or a negative errno.
- `fn tula_builder_write_file_signed(b, path, sk) -> file_len | <0` *(1.4.0)* —
  the same, Ed25519-signed: byte-identical to `tula_builder_finish_signed(b, sk)`.
  The content is written, mapped back read-only and signed (no heap copy), and
  the signature appended. Signing reads the content twice through sigil's
  SHA-512 (about 18 MB/s today), so a multi-GB file takes minutes.
- `fn tula_read_file(path) -> r | 0` — read into a fresh heap buffer, then
  `tula_open` (full validation). The allocation happens only after the file is
  known to hold the total its header declares. One allocation is capped at
  2 GiB: for bigger files use `tula_open_mmap` or `tula_read_file_into`.
- `fn tula_file_len(path) -> total | -1` *(1.4.0)* — the total a file's header
  declares, once the file is known to hold it. That's the buffer size
  `tula_read_file_into` needs.
- `fn tula_read_file_into(path, buf, cap) -> buf | 0` *(1.4.0)* — read into the
  caller's buffer, then validate. Returns 0 if the file is bigger than `cap`. The
  buffer can be reused across files, and can be bigger than 2 GiB (e.g. an
  anonymous mapping).
- `fn tula_open_mmap(path) -> r | 0` — zero-copy read-only mmap, validated. A file
  shorter than its header's total is rejected before mapping, and a mapped file
  that fails validation is unmapped again. Release with `fn tula_close_mmap(r)`
  (`tula_close_mmap(0)` is a no-op). The mapping is live: map only files no other
  process writes (`SECURITY.md`).

tula files are self-describing (the header carries the total length). Both
readers compare it with the file's real size via `lseek(SEEK_END)`, not
`stat()`, and reject a source that can't be sized (a pipe). A file *longer* than
its total opens, and the readers take exactly the declared bytes.

## Consumer checks — `src/check.cyr` *(1.2.0)*

- `fn tula_validate_strict(buf, len) -> TULA_OK | TULA_ERR_*` — runs
  `tula_validate` (returning its code on failure), then accepts only a
  **canonical** buffer, exactly what a correct tula writer produces:
  - `TULA_ERR_LAYOUT`: `len` is not exactly the file's total; a tensor's payload
    doesn't start where the previous one's 8-aligned end left off (overlap, gap,
    misalignment, reordering); the payload runs past the last tensor; or a
    padding byte, or a name byte after the NUL, is non-zero.
  - `TULA_ERR_DTYPE`: an unknown dtype.
  - `TULA_ERR_SHAPE`: a negative dim, a non-zero dim past `ndim`, or `data_len` ≠
    `tula_packed_len(dtype, nelems)` (a 0-dim entry holds one element).
  - `TULA_ERR_NAMES` *(1.3.0)*: a names table is present but not canonical.
    That means records out of order or pointing at the table, names not packed
    in record order, a name of 47 bytes or fewer, a NUL inside a name, or an
    entry whose field isn't its name's key.
  - `TULA_ERR_META` *(1.6.0)*: a metadata table is present but not canonical.
    That means keys out of order or repeated, a bad key, a value that isn't UTF-8
    or holds a NUL, not packed in order, or past the caps.
  - `TULA_ERR_DUP_NAME`: two tensors share a name (for long names, a key).
  - `TULA_ERR_OOM`: no memory for the duplicate check (over 512 tensors).

  Duplicates are found by a heapsort of (name hash, entry) records, worst case
  O(n log n) whatever the names: untrusted names never go into a hash table, so
  a crafted file can't make the check quadratic. ~210 ns per tensor
  ([benchmarks](benchmarks.md)). Structure only; authenticity is
  `tula_verify_required`. To read a file strictly, call `tula_read_file` /
  `tula_open_mmap`, then `tula_validate_strict(r, tula_total_len(r))`.
- `fn tula_find_scale(r, e, need) -> se | 0` — the `"<name>.scale"` sidecar of
  entry `e` (ADR 0002), checked for an unpack that will read `need` scales. It
  must exist, be f64, pass `tula_entry_payload_ok`, and hold at least `need`
  elements in at least `need * 8` bytes. `need` is 1 for a per-tensor scale, the
  row count for per-row, or `tula_nf4_blocks(nelems, block)` for NF4. Returns 0
  for `need < 1`. *1.3.0:* "<name>" is the entry's **full** name, and a sidecar
  name over 47 chars is found through the names table. A file without one has no
  such sidecar, so there, as in 1.2.0, a name over 41 chars returns 0.

## Metadata — `src/meta.cyr` *(1.6.0, ADR 0008)*

- `fn tula_meta_count(r) -> P` — number of pairs (0 = none).
- `fn tula_meta_get(r, key) -> value | 0` — the value under `key`, as a
  NUL-terminated pointer into the file (zero-copy). A binary search, O(log P).
- `fn tula_meta_key(r, i) -> key | 0` · `fn tula_meta_value(r, i) -> value | 0` —
  pair `i`, in key order (`0 ≤ i < tula_meta_count(r)`).

Every record is bounds-checked when read; one that doesn't hold up reads as
absent. `tula_validate_strict` requires the table to be canonical
(`TULA_ERR_META` otherwise).

## Name index — `src/index.cyr` *(1.5.0, ADR 0007)*

For many lookups on one file: `tula_find` / `tula_find_name` scan the manifest,
so looking up every tensor is O(n²). At 4,096 tensors that's 44.8 ms by scan and
3.1 ms through the index, build included.
- `fn tula_index_new(r) -> ix | 0` — build the index of an opened buffer: a
  sorted array of (name hash, canonical name) records in one private mapping
  (48 + 64·n bytes). Worst case O(n log n) for any names. It is never a hash
  table, so a crafted file can't flood it. The index points into `r`, so use it
  only while `r` is valid. 0 if the mapping fails.
- `fn tula_index_find(ix, name) -> e | 0` — O(log n), and **exactly**
  `tula_find_name(r, name)`'s answer: the first matching entry, any length, a
  long name confirmed against the names table.
- `fn tula_index_find_scale(ix, e, need) -> se | 0` — `tula_find_scale` through
  the index.
- `fn tula_index_free(ix)` — release it (`0` is a no-op).

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
- `fn tula_nf4_blocks(n, block) -> ceil(n/block)` (0 for `block <= 0`) · `fn
  tula_nf4_bytes(n) -> ceil(n/2)`
- `fn tula_nf4_pack(src_f64, n, block, scales_f64, nibbles) -> n_blocks` — writes
  per-block absmax into `scales` (store as sidecar) and 4-bit codes into
  `nibbles`.
- `fn tula_nf4_unpack(nibbles, scales, n, block, dst_f64) -> n` — reads
  `tula_nf4_blocks(n, block)` scales. `pack` and `unpack` return 0 and write
  nothing for `block <= 0`.
- `fn tula_nf4_get(nibbles, i) -> code 0..15` · `fn tula_nf4_level(i) -> f64` (the
  codebook). `TULA_NF4_BLOCK = 64` (typical block size).

**F32 / F16 / BF16** *(1.3.0, ADR 0005)*: IEEE 754 conversions to and from f64,
done in integer arithmetic, so the bytes never depend on the process's FP mode.
- f64 → narrow is round to nearest, ties to even, **directly from the f64** (BF16
  and F16 are not rounded through F32). Overflow gives ±inf, underflow the
  correctly rounded subnormal or ±0 (no flush), the sign of zero is kept, and NaN
  stays NaN with its sign and top payload bits, quiet.
- narrow → f64 is exact; NaN comes back quiet with its payload.
- These are the same results as x86/aarch64 hardware in the default mode. F16
  and BF16 are checked exhaustively (all 65,536 codes and every midpoint), F32
  against the hardware.
- Scalars: `tula_f64_to_f32(x)` / `tula_f32_to_f64(h)`, `tula_f64_to_f16` /
  `tula_f16_to_f64`, `tula_f64_to_bf16` / `tula_bf16_to_f64`. Bit patterns in an
  i64; the narrow side uses its low 32 or 16 bits.
- Arrays: `tula_f32_pack(src_f64, n, dst) -> n*4` · `tula_f32_unpack(src, n,
  dst_f64) -> n`, and the same for `f16` / `bf16` (`-> n*2`). Little-endian.

**Payload-length guard** (untrusted-input discipline):
- `fn tula_packed_len(dtype, nelems) -> bytes | -1` — expected packed byte length.
- `fn tula_entry_payload_ok(e) -> 1 | 0` — overflow-safe check that an entry's
  `data_len` is large enough for its dtype+shape. **Run it before any unpack on a
  foreign entry** (a lying `shape` could otherwise drive an over-read), and on
  the entry's `.scale` sidecar. 0 for any negative dim; 1 for an empty tensor (a
  zero dim), an unknown dtype, or a 0-dim entry (no element count, so no
  contract).

Double-quant composes: int8-quantize a `"<name>.scale"` tensor and store its own
`"<name>.scale.scale"` — the same convention, one level down.

---

## Minimal consumer flow

```
# write
b = tula_builder_new()                  # or tula_builder_new_cap(n) past 256 tensors
if (tula_builder_add_checked(b, "w", TULA_DT_F64, shape, ndim, data, len) != 0) { ...fix input... }
tula_builder_set_meta(b, "hf.architecture", "LlamaForCausalLM")   # 1.6.0
buf = tula_builder_finish_signed(b, sk)
tula_write_file("model.tula", buf, tula_total_len(buf))

# read (untrusted)
r = tula_read_file("model.tula")        # 0 if malformed
if (r == 0) { ...reject... }
if (tula_validate_strict(r, tula_total_len(r)) != TULA_OK) { ...reject... }
if (tula_verify_required(r, pk) != TULA_OK) { ...reject... }
e = tula_find_name(r, "w")              # any length (1.3.0); tula_find for <= 47
if (e == 0) { ...reject... }
# many lookups: ix = tula_index_new(r); e = tula_index_find(ix, name); tula_index_free(ix)
arch = tula_meta_get(r, "hf.architecture")    # 1.6.0; 0 if absent
if (tula_entry_payload_ok(e) == 0) { ...reject... }
p = tula_entry_data(r, e)               # in-bounds, zero-copy
# a quantized tensor: se = tula_find_scale(r, e, need); if (se == 0) { ...reject... }
```

`tula_validate_strict` and `tula_verify_required` are 1.2.0; `tula_find_name`
and `tula_builder_add_long` are 1.3.0; the streaming writers are 1.4.0; the name
index is 1.5.0; metadata is 1.6.0. On 1.0–1.1, use `tula_verify(r, pk) !=
TULA_SIG_OK` and check the consistency rules yourself.

A complete runnable example is in [`examples/consumer.cyr`](../examples/consumer.cyr).
