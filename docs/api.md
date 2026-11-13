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
| `TULA_DT_I16`     | 7 | signed 16-bit, two's complement, LE, `data_len = nelems*2` *(1.7.0)* |
| `TULA_DT_I32`     | 8 | signed 32-bit, two's complement, LE, `data_len = nelems*4` *(1.7.0)* |
| `TULA_DT_I64`     | 9 | signed 64-bit, two's complement, LE, `data_len = nelems*8` *(1.7.0)* |
| `TULA_DT_U8`      | 10 | unsigned 8-bit, `data_len = nelems` *(1.7.0)* |
| `TULA_DT_BOOL`    | 11 | one byte each, 0 or 1 only, `data_len = nelems` *(1.7.0)* |
| `TULA_DT_F8_E4M3` | 12 | OCP FP8 E4M3 (no inf; NaN `S.1111.111`), `data_len = nelems` *(1.8.0)* |
| `TULA_DT_F8_E5M2` | 13 | OCP FP8 E5M2 (IEEE-like), `data_len = nelems` *(1.8.0)* |
| `TULA_DT_INT4`    | 14 | signed 4-bit codes, 2/byte, low nibble first, `data_len = ceil(nelems/2)` *(1.8.0)* |
| `TULA_DT_UINT4`   | 15 | unsigned 4-bit codes 0..15, INT4's layout, `data_len = ceil(nelems/2)` *(1.12.0)* |

Quantized dtypes store their scale(s) as a **sidecar** `f64` tensor named
`"<name>.scale"` (ADR 0002) — the codec never interprets it.

**Integer and boolean tensors** *(1.7.0, ADR 0009)* are raw values with no
helpers: element `i` is one load at `p + i × width` (`p` =
`tula_entry_data(r, e)`). Signed 8-bit is `TULA_DT_INT8`. In cyrius, `load8` /
`load16` / `load32` zero-extend and `>>` is a logical shift, so an I16 or I32 is
sign-extended by subtraction:

```cyrius
var v16 = load16(p + i * 2);
v16 = v16 - ((v16 & 0x8000) << 1);          # I16
var v32 = load32(p + i * 4);
v32 = v32 - ((v32 & 0x80000000) << 1);      # I32
var v64 = load64(p + i * 8);                 # I64: already signed
var u = load8(p + i);                        # U8, or BOOL (0 / 1 once strict passed)
```

`tula_validate_strict` rejects a BOOL byte other than 0 or 1 (`TULA_ERR_VALUE`);
the plain reader and `tula_entry_payload_ok` check sizes only. A 1.2–1.6 strict
validator returns `TULA_ERR_DTYPE` for these dtypes; its plain reader opens,
verifies and resolves the file as before.

**FP8 and INT4** *(1.8.0, ADRs 0010 and 0011)* have conversion helpers (see the
dtype helpers below). Every FP8 byte is a value. An INT4 tensor with an odd
count leaves the last byte's high nibble zero, and strict rejects a nonzero one
(`TULA_ERR_VALUE`). INT4's per-block scales are an f64 `"<name>.scale"`
sidecar, like NF4's. A 1.2–1.7 strict validator returns `TULA_ERR_DTYPE` for
codes 12–14.

**UINT4** *(1.12.0, ADR 0015)* is INT4's layout with unsigned codes and two
sidecars, `"<name>.scale"` and `"<name>.min"`: `value = code × scale + min`
(GGUF Q4_1). Strict's nibble rule is INT4's. A 1.2–1.11 strict validator returns
`TULA_ERR_DTYPE` for code 15.

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
| | | | `TULA_ERR_VALUE` | 19 |
| | | | `TULA_ERR_SHARDS` | 20 |
| | | | `TULA_ERR_OTHER` | 99 |

Codes 13–16 are new in 1.2.0, returned by the checked add and the strict
validator. 17 is new in 1.3.0 (a malformed names table, from the strict
validator). 18 is new in 1.6.0 (a bad metadata key or value from the writer, or
a malformed metadata table from the strict validator). 19 is new in 1.7.0 (a
payload value its dtype doesn't allow, from the strict validator: a BOOL byte
other than 0 or 1, and from 1.8.0 an odd-length INT4 tensor's last high nibble
that isn't zero). 20 is new in 1.11.0. It reports a malformed shard set: a
manifest whose shard list isn't canonical (strict), a builder that mixes shards
and tensors, or a shard its manifest doesn't match.

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
  `data_len` equal to `tula_packed_len(dtype, nelems)`, *(1.7.0)* each BOOL
  payload holding only 0 and 1 bytes and *(1.8.0)* each odd-length INT4 tensor's
  last high nibble zero, writes files `tula_validate_strict` accepts. Payloads
  are never read at add.
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
  `path`, then the directory is fsync'd. On failure `path` is untouched and no
  temp is left. An existing file keeps its exact permission bits; a symlink at
  `path` is replaced, not written through.

Both write in requests of at most 1 GiB (1.6.2; through the stdlib before), so a
buffer over INT_MAX bytes works on macOS, which refuses a bigger request.
- `fn tula_builder_write_file(b, path) -> file_len | <0` *(1.4.0, ADR 0006)* —
  **stream** the builder's file to disk: exactly the bytes `tula_builder_finish(b)`
  returns, never held in memory, so there is no 2 GiB cap. The header, manifest
  and names table go through a 64 KiB staging buffer; each payload is written
  straight from the caller's buffer. Atomic: a temp with the target's mode is
  written, fsync'd, renamed over `path`, then the directory fsync'd. On Linux
  *(1.6.1)* the temp is a nameless `O_TMPFILE` inode, linked under a random
  sibling name only once complete; elsewhere (or without `O_TMPFILE` or `/proc`)
  it is a random `O_EXCL` sibling `<path>.tula-<16 hex>.tmp`. On any failure the
  temp is removed and `path` is untouched. A symlink at `path` is replaced, not
  written through. Returns the file's length or a negative errno.
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
- `fn tula_open_protected(path) -> r | 0` *(1.10.0, ADR 0013)* — a reader whose
  bytes nothing done to the file afterwards can change: a rewrite in place or a
  truncation by another process never reaches it, and can't make it SIGBUS.
  Release with `tula_close_mmap`.
  - **An fs-verity file** (Linux: ext4 with `-O verity`, f2fs, btrfs) is mapped
    zero-copy, as `tula_open_mmap` does, because the kernel refuses every write
    and truncation to it. Storage returning data that fails verification still
    raises SIGBUS on the touching read, as any mapping of a failing disk does.
  - **Any other file** is read into a private anonymous mapping and validated
    there. That costs one read (about 8.8 GB/s from the page cache here) and
    memory equal to the file, up to `TULA_READ_MAX_BYTES`, with no 2 GiB cap.
  - The fs-verity check runs on the descriptor that is then mapped or read, so a
    rename in between can't swap the file. The immutable attribute (`chattr +i`)
    isn't trusted, because some filesystems let a writer that was already open
    keep writing. On macOS the open always copies.

  Choose `tula_open_mmap` when you control who writes the file, and
  `tula_open_protected` when you don't. A store that seals its checkpoints with
  fs-verity gets both.

tula files are self-describing (the header carries the total length). The
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
  - `TULA_ERR_VALUE` *(1.7.0)*: a BOOL byte other than 0 or 1 (ADR 0009), a
    word compare per 8 elements, ~4 GB/s; *(1.8.0)* an odd-length INT4
    tensor whose last high nibble isn't zero (ADR 0011), one byte read. These
    are the only rules that read tensor values.
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
- `fn tula_find_sidecar(r, e, suffix, need) -> se | 0` *(1.12.0, ADR 0015)* —
  entry `e`'s `"<full name><suffix>"` sidecar, checked as `tula_find_scale`
  checks it: `".min"` for UINT4, or any suffix. `tula_find_scale` is this
  lookup with `".scale"`.
- `fn tula_index_find_scale(ix, e, need) -> se | 0` — `tula_find_scale` through
  the index. `fn tula_index_find_sidecar(ix, e, suffix, need)` *(1.12.0)* is
  `tula_find_sidecar` through it.
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

**FP8 E4M3 / E5M2** *(1.8.0, ADR 0010)*: the OCP 8-bit floats, to and from f64
in integer arithmetic.
- f64 → FP8 rounds to nearest, ties to even, directly from the f64, keeping
  subnormals and the sign of zero. **No saturation:** a value that rounds past
  the largest finite becomes NaN in E4M3 (over 464; the largest is 448) and ±inf
  in E5M2 (from 61,440; the largest is 57,344), and so does ±inf. A quantizer
  that wants clipping clamps first. NaN stays NaN with its sign (E5M2 keeps the
  top payload bit, quiet).
- FP8 → f64 is exact; NaN comes back quiet with its sign.
- Checked exhaustively: all 256 codes of each, every midpoint, and an oracle.
- Scalars: `tula_f64_to_e4m3(x)` / `tula_e4m3_to_f64(h)`, `tula_f64_to_e5m2` /
  `tula_e5m2_to_f64` (the FP8 side in the low 8 bits).
- Arrays: `tula_e4m3_pack(src_f64, n, dst) -> n` · `tula_e4m3_unpack(src, n,
  dst_f64) -> n`, and the same for `e5m2`. One byte each.

**INT4** *(1.8.0, ADR 0011)*: signed 4-bit codes (−8..7), two per byte, element
2k in the low nibble; blockwise symmetric, one f64 scale per block in the
`"<name>.scale"` sidecar, `value = code × scale`.
- `fn tula_int4_bytes(n) -> ceil(n/2)` · `fn tula_int4_blocks(n, block) ->
  ceil(n/block)` (0 for `block <= 0`) · `TULA_INT4_BLOCK = 32` (GGUF Q4_0's).
- `fn tula_int4_get(codes, i) -> -8..7`.
- `fn tula_int4_pack(src_f64, n, block, scales_f64, codes) -> n_blocks` — llama.cpp's
  Q4_0 reference rule in f64: `m` is the block's value of largest magnitude, `d
  = m / −8`, and each code is `x / d` rounded half up, clamped to −8..7. So `d`
  can be negative, and an all-zero block gets `d = +0` and codes 0. An odd
  count's last high nibble is left zero.
- `fn tula_int4_unpack(codes, scales, n, block, dst_f64) -> n` — reads
  `tula_int4_blocks(n, block)` scales. Both return 0 and write nothing for
  `block <= 0`.
- Find the sidecar with `tula_find_scale(r, e, tula_int4_blocks(nelems, block))`.
  To import GGUF Q4_0 losslessly, store `q − 8` per code (`q XOR 8`), move the
  elements from Q4_0's block layout (byte `j` holds elements `j` and `j + 16`)
  into element order, and widen each f16 `d` to f64.

**UINT4** *(1.12.0, ADR 0015)*: unsigned 4-bit codes 0..15 in INT4's layout
(sizes are `tula_int4_bytes` / `tula_int4_blocks`), with one f64 scale `d` per
block in `"<name>.scale"` and one f64 minimum `m` in `"<name>.min"`:
`value = code × d + m`.
- `fn tula_uint4_get(codes, i) -> 0..15`.
- `fn tula_uint4_pack(src_f64, n, block, scales_f64, mins_f64, codes) ->
  n_blocks` — llama.cpp's Q4_1 reference rule in f64.
  - `m` is the block's smallest value and `d = (max − min) / 15`.
  - Each code is `(x − m) / d` rounded half up and clamped to 0..15, so the
    minimum gets 0 and the maximum 15.
  - A block of equal values gets `d = +0` and codes 0.
  - NaNs take part in no comparison and get code 0.
- `fn tula_uint4_unpack(codes, scales, mins, n, block, dst_f64) -> n` — each
  value is `f64_mul(code, d)`, then `f64_add` of `m`: two IEEE operations, no
  fused multiply-add. Both return 0 and write nothing for `block <= 0`.
- Find the sidecars with `tula_find_sidecar(r, e, ".scale", nb)` and
  `tula_find_sidecar(r, e, ".min", nb)`, `nb = tula_int4_blocks(nelems, block)`
  (or the index and set forms). `tula_unpack_par` doesn't cover UINT4, which
  needs two sidecars, and returns −1 for it. Use `tula_uint4_unpack_par`
  (1.13.0, below).
- **To import GGUF Q4_1 losslessly**, move the codes from the block layout
  (byte `j` holds elements `j` and `j + 16`) into element order (no XOR: Q4_1's
  codes are already unsigned), and widen each block's f16 `d` and `m` to f64.
  The values tula's unpack gives are the f64 of `q × d + m`. They can differ in
  the last bits from llama.cpp's f32 arithmetic; the stored file is exact.

**Payload-length guard** (untrusted-input discipline):
- `fn tula_packed_len(dtype, nelems) -> bytes | -1` — expected packed byte length
  (`nelems × width` for the raw dtypes, including 1.7.0's integers and BOOL and
  1.8.0's FP8; `ceil(nelems/2)` for INT4 and, from 1.12.0, UINT4).
- `fn tula_entry_payload_ok(e) -> 1 | 0` — overflow-safe check that an entry's
  `data_len` is large enough for its dtype+shape. **Run it before any unpack on a
  foreign entry** (a lying `shape` could otherwise drive an over-read), and on
  the entry's `.scale` sidecar. 0 for any negative dim; 1 for an empty tensor (a
  zero dim), an unknown dtype, or a 0-dim entry (no element count, so no
  contract).

Double-quant composes: int8-quantize a `"<name>.scale"` tensor and store its own
`"<name>.scale.scale"` — the same convention, one level down.

**Speed** *(1.9.0)*: the array helpers are faster, with the same output bit for
bit, and no signature or contract changed. The FP8 unpacks and int8's
dequant read a 256-entry table from 1,024 elements, and ternary's unpack from
1,024 trits. NF4 and INT4 build each block's 16 products once, from a block of
16. Each float format has its own loop. In 1.9.1 the F16 and BF16 unpacks read
a per-call table of all 65,536 codes from 262,144 elements, and NF4 pack finds
each code through 15 exact thresholds instead of scanning the codebook (the
scan's answer on every input). Numbers are in [`benchmarks.md`](benchmarks.md).

---

## Parallel unpack — `src/par.cyr` *(1.9.0, ADR 0012)*

- `fn tula_unpack_par(dtype, src, n, scales, block, dst, nthreads) -> n | -1`
  — runs the dtype's unpack helper over a tensor on up to `nthreads` threads,
  the caller's included. The output is the serial helper's, bit for bit, at any
  thread count.
  - **Arguments by dtype**, as the serial helpers take them:
    - F32, F16, BF16, F8_E4M3, F8_E5M2: `scales` and `block` are unused;
    - INT8: `scales` points at the one f64 scale;
    - NF4, INT4: `scales` is f64 per `block` elements (`block` > 0);
    - TERNARY: `dst` is i64 trits.
  - **Returns −1, writing nothing**, for:
    - a dtype it doesn't cover: F64, the integers, BOOL, unknown codes, and
      (1.12.0) UINT4, whose unpack needs two sidecars;
    - `n < 0`;
    - NF4 or INT4 with `block <= 0`.

    `n = 0` returns 0 without reading `scales`.
  - **Threads**: the caller chooses `nthreads`, and tula doesn't probe the
    machine. A count below 1 counts as 1. A call uses at most
    `TULA_PAR_MAX_THREADS` (64), and gives each thread at least
    `TULA_PAR_MIN_CHUNK` (65,536) elements, so a smaller tensor runs on the
    caller's thread alone. A thread that fails to start has its slice run on the
    caller's thread. Where the stdlib's `THREADS_CONCURRENT` isn't 1 (agnos,
    cx), the whole call runs serially. The two constants tune the split only,
    so they may change in a MINOR (STABILITY.md); the output never depends on
    them.
  - **Cost**: each call starts and joins its threads; there is no pool. Each
    thread started leaves about 4 KiB of the stdlib's bookkeeping on cyrius's
    bump allocator, which has no free.
  - Like the serial helpers it trusts its arguments: run `tula_entry_payload_ok`
    on a foreign entry and its `.scale` sidecar first.
- `fn tula_uint4_unpack_par(codes, scales, mins, n, block, dst, nthreads) -> n |
  -1` *(1.13.0, ADR 0016)* — `tula_uint4_unpack` on up to `nthreads` threads.
  It splits as `tula_unpack_par` does and gives the same output bit for bit.
  Returns −1, writing nothing, for `n < 0` or `block <= 0`, and 0 for `n = 0`.
  A separate call because `tula_unpack_par`'s frozen signature has one sidecar
  and UINT4 needs two.

---

## Shard sets — `src/shard.cyr` *(1.11.0, ADR 0014)*

A model in several files. The **manifest** is an ordinary tula file with no
tensors, signed. Its reserved metadata key `tula.shards` lists the **shards**,
one line each: `<sha256> <size> <name>\n`.
- 64 lowercase hex digits of the SHA-256 over the shard's first `size` bytes;
- the shard's total length, in decimal;
- its file name in the manifest's directory: 1–255 bytes of printable ASCII or
  UTF-8, with no `/`, `\` or space, and not `.` or `..`.

Lines are in strictly increasing byte order of name, with 1 to
`TULA_SHARDS_MAX` (4,096) shards. Signing the manifest signs every digest, so
the shards need no signatures of their own. A set verifies with one Ed25519
check over a small file and a SHA-256 of each shard, run in parallel: about
1.2 GB/s at 8 threads here, against 17 MB/s for one signed file. Shards are
ordinary strict-valid tula files, none of them a manifest, and tensor names are
unique across the set. `tula_validate_strict` returns `TULA_ERR_SHARDS` for a
manifest whose list isn't canonical, or that holds any entry but its metadata
table.

**Write:**
- `fn tula_builder_set_shards(b, paths, n, nthreads) -> 0 | TULA_ERR_* | <0` —
  make `b` the manifest for the `n` shard files at `paths` (an array of `n`
  cstrings). Each shard is opened mapped, strict-validated and hashed, on up to
  `nthreads` threads, then listed by file name (each path's part after its last
  `/`). Errors leave the builder unchanged:
  - a negative errno: a shard can't be opened;
  - a validate or strict code: a shard isn't strict-valid;
  - `TULA_ERR_SHARDS`: `n` outside 1..4,096, the builder holds tensors, a shard
    is a manifest, a file name isn't allowed, or two shards share a name;
  - `TULA_ERR_OOM`.

  Calling it again replaces the list. A manifest builder refuses tensors: every
  add returns `TULA_ERR_SHARDS`. Set the set's own metadata on it with
  `tula_builder_set_meta`. Write it into the shards' directory, signed
  (`tula_builder_finish_signed` or `tula_builder_write_file_signed`).

**Read:**
- `fn tula_set_open(path, pk, flags, nthreads, rc) -> set | 0`.
  - **The manifest** is read through `tula_open_protected` and strict-validated.
    With `pk` its signature is required; with `pk = 0` it isn't checked, and the
    digests then only catch corruption.
  - **Each shard** is mapped (`flags = 0`), or opened through
    `tula_open_protected` with `TULA_SET_PROTECTED` (1).
  - **The checks:** every size and SHA-256, on up to `nthreads` threads; every
    shard strict-valid; no shard a manifest; no tensor name in two shards.
  - **Failure:** `rc` (two words, or 0) gets the code and the shard it concerns
    (`-1` for the manifest). The code is a negative errno; a validate, strict or
    `tula_verify_required` code; `TULA_ERR_SHARDS` (not a manifest, a shard's
    size or digest, a nested manifest); `TULA_ERR_DUP_NAME`; or `TULA_ERR_OOM`.
  - **Trust:** a mapped set, like `tula_open_mmap`, holds only while nobody
    rewrites its files.
- `fn tula_set_find(set, name) -> e | 0` — any tensor of the set by its full
  name, O(log n).
- `fn tula_set_reader(set, e) -> r | 0` — the shard holding `e`, for its
  accessors: `tula_entry_data(tula_set_reader(set, e), e)`.
- `fn tula_set_find_scale(set, e, need) -> e | 0` — `e`'s `.scale` sidecar in
  any shard, checked as `tula_find_scale` checks it. `fn tula_set_find_sidecar(set,
  e, suffix, need)` *(1.12.0)* finds any suffix's (`".min"`).
- `fn tula_set_shards(set)`, `fn tula_set_shard(set, i) -> r | 0` (in name
  order), `fn tula_set_tensors(set)` (across the set, without each shard's own
  names and metadata tables), `fn tula_set_manifest(set) -> r` (the set's
  metadata: `tula_meta_get(tula_set_manifest(set), key)`).
- `fn tula_set_close(set)` — release every shard, the manifest and the set
  (`0` is a no-op).

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
r = tula_read_file("model.tula")        # 0 if malformed; tula_open_protected for a file others may write (1.10.0)
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
# a sharded model (1.11.0): set = tula_set_open("model.tula", pk, 0, 8, rc);
#   e = tula_set_find(set, name); r = tula_set_reader(set, e); ...; tula_set_close(set)
# to f64 on 8 threads (1.9.0); -1 for a dtype with no unpack helper:
#   n = tula_entry_nelems(e)
#   tula_unpack_par(tula_entry_dtype(e), p, n, tula_entry_data(r, se), block, dst, 8)
```

`tula_validate_strict` and `tula_verify_required` are 1.2.0; `tula_find_name`
and `tula_builder_add_long` are 1.3.0; the streaming writers are 1.4.0; the name
index is 1.5.0; metadata is 1.6.0; `tula_unpack_par` is 1.9.0;
`tula_open_protected` is 1.10.0; shard sets are 1.11.0; UINT4 and
`tula_find_sidecar` are 1.12.0; `tula_uint4_unpack_par` is 1.13.0. On 1.0–1.1, use `tula_verify(r, pk) !=
TULA_SIG_OK` and check the consistency rules yourself.

A complete runnable example is in [`examples/consumer.cyr`](../examples/consumer.cyr).
