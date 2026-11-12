# Changelog

All notable changes to `tula` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is SemVer. As of
**v1.0** the public surface is frozen — see [`STABILITY.md`](STABILITY.md)
(format v1 stable; MINOR = additive-only; MAJOR = format/API break).

## [Unreleased]

**Integer and boolean dtypes** (1.7.0). An additive MINOR with no format change
(ADR 0009). A checkpoint's ids, masks, buffers and packed integer codes can be
stored losslessly and under their own types. A file that doesn't use them is
byte for byte what 1.6.2 writes. Diffed against 1.6.2 on 400 random builders
(dtypes 0–6 and an unknown one) and 10,000 mutations of them:
- the same bytes from `finish` and `finish_signed`, and the same return code
  from every add, metadata set and verify;
- the same verdicts, `payload_ok`, `nelems`, find-name and index answers, and
  metadata;
- the only differences are the expected ones, for mutations that set a dtype
  field to 7–11.

**1.6.2 reads 1.7 files**: it opens them, verifies them, and resolves their long
names and metadata; its strict validator returns `TULA_ERR_DTYPE` for the new
codes, as 1.2 did for ADR 0005's floats.

### Added

- **`TULA_DT_I16` (7), `TULA_DT_I32` (8), `TULA_DT_I64` (9), `TULA_DT_U8` (10),
  `TULA_DT_BOOL` (11)** (ADR 0009). Raw little-endian, `data_len = nelems ×
  width`; I16/I32/I64 are two's complement, BOOL is one byte, 0 or 1.
  - Signed 8-bit stays `TULA_DT_INT8`: its bytes are already an int8 tensor.
  - No conversion helpers: each element is one load. `docs/api.md` shows the
    sign extension for I16 and I32 (cyrius's loads zero-extend, and `>>` is
    logical, so `(v << 48) >> 48` doesn't sign-extend).
  - `tula_packed_len`, `tula_entry_payload_ok` and `tula_validate_strict` know
    the widths.
- **`TULA_ERR_VALUE` (19)**: a payload value its dtype doesn't allow.
  `tula_validate_strict` returns it for a BOOL byte other than 0 or 1. It is the
  first strict rule that reads tensor values: one 64-bit compare per 8 elements,
  ~4 GB/s (`docs/benchmarks.md`). Padding is checked first, so a bad pad byte
  after a mask is still `TULA_ERR_LAYOUT`.
- **ADR 0009** records the codes, the encodings, the BOOL rule, and what was left
  out: bit-packed BOOL, a lenient "nonzero is true", U16/U32/U64, a second
  int8 code, element-read helpers, and converting integers to f64.

### Changed

- **`tula_builder_add_checked`'s promise** now also needs each BOOL payload to
  hold only 0 and 1 bytes (it never reads payloads), as it already needed each
  `data_len` to be the packed length.
- **`tests/tcyr/ints.tcyr`** (new, 61 assertions):
  - the codes and widths;
  - a round trip at each dtype's extremes (INT16/32/64 min and max, 2⁵³ + 1,
    255), read back with the documented sign extension;
  - the exact-size rule, where a short or long payload is `TULA_ERR_SHAPE`;
  - each of a 13-byte mask's bytes set to all 256 values: strict accepts
    exactly 0 and 1;
  - a 0-dim and an empty BOOL;
  - a 1 MiB mask with a bad first and a bad last byte;
  - `payload_ok`;
  - the streaming writer equal to `finish`, with a long name.
- **Two tests used 7 and 9 as "unknown" dtypes** (`floats.tcyr`,
  `strict.tcyr`); they now use 12 (the next free code) and 99.
- **The fuzzer** (3,204,500 iterations, 0 faults):
  - its consumer discipline reads every element of the new dtypes;
  - its brute-force strict check requires BOOL bytes of 0 or 1;
  - phase H's builders draw from all twelve dtypes, with 12 as the unknown
    one, and BOOL payloads from a 0/1 pool;
  - a new phase I makes 300,000 mutations of a file holding all five, aimed at
    BOOL bytes, dtype fields and shapes;
  - it now holds `data_len` to its own size table, so a wrong width in
    `tula_packed_len` can't hide behind itself. Before this, a seeded I64 width
    bug passed the fuzzer: the over-read stayed inside the buffer.

  89,657 strict accepts, all confirmed by brute force (1.6.2: 26,968), and
  13,694 BOOL rejections. Three seeded bugs are each caught: strict's BOOL check
  removed (11,454 breaches), its mask widened to allow 2 and 3 (82), and an I64
  width of 4 (6,400).
- **`make realmodels`** gains a sixth inventory: Llama-2-7B in AutoGPTQ's 4-bit,
  group-128 layout. Each linear layer is `qweight` I32 [in/8, out], `qzeros` I32
  [in/128, out/8], `scales` F16 [in/128, out] and `g_idx` I32 [in]; with the
  F16 embeddings, norms and `lm_head` that's 963 tensors, written signed,
  strict-validated, verified and resolved by name.
- **The reference consumer** stores a BERT-style `position_ids` (I64), an
  attention mask (BOOL) and signed I32 offsets, and reads them back.
- **Bench**: strict over a 16 MiB BOOL tensor, 4.0 ms; the same bytes as U8,
  1 µs. Strict over 200 tensors is unchanged from 1.6.2 on the same machine.
- **Roadmap**: 1.7.0 is done. FP8 and int4 (1.8.0) take codes from 12.

## [1.6.2] - 2026-11-12

**macOS is a hard gate.** A patch: no new function, dtype or convention, and no
format change. Every call writes the same bytes as in 1.6.1: diffed for
`tula_write_file` and `tula_write_file_atomic` against the stdlib calls 1.6.1
made, and the streaming writers still equal `tula_builder_finish(_signed)` in
the fuzzer's phase H.

### Fixed

- **`tula_write_file` and `tula_write_file_atomic` over 2 GiB on macOS**, 1.6.1's
  known limit. Both handed their buffer to the stdlib (`file_write_all`,
  `file_write_atomic`), whose loop asks for the whole remainder in one request.
  macOS refuses a request over INT_MAX bytes with EINVAL, so a buffer over
  2 GiB − 1 failed there (with `path` untouched, for the atomic one). Both now
  write through tula's own loop, at most 1 GiB per request, as the readers and
  the streaming writers have since 1.6.1. The stdlib's loops are unchanged
  (cyrius issue `2026-11-05-tula-io-loops-one-request-over-int-max-fails-on-macos.md`
  is open); tula no longer goes through them.
  - Reproduced on Linux with 1.6.1's probe (a read or write over INT_MAX bytes
    returns -EINVAL, as on Darwin). There 1.6.1 fails the new `make bigfile` at
    `tula_write_file_atomic`, and a fix to the atomic writer alone fails it at
    `tula_write_file`. 1.6.2 passes.
  - `tula_write_file_atomic` now uses the streaming writers' named temp: a
    random `<path>.tula-<16 hex>.tmp` created `O_CREAT|O_EXCL`, written,
    fsync'd and renamed. Its guarantees are unchanged: `path` is untouched on
    any failure, no temp is left behind, a symlink at `path` is replaced, and an
    existing file keeps its exact permission bits. Three details change, each
    toward those guarantees:
    - a failed `fsync` is an error, and `path` is left as it was (the stdlib
      ignored it and renamed a file that might not be on disk);
    - the directory is fsync'd after the rename (best effort), as the streaming
      writers do, so the rename survives a crash;
    - the exact mode is set once the bytes are written, not at create, so the
      temp is never more permissive than its create allowed while it is
      written (the stdlib widened it first).

    As for the streaming writers, a path within 32 bytes of `PATH_MAX` is
    `-ENAMETOOLONG`.
  - `tula_write_file` returns a failed `close` as an error (the stdlib ignored
    it). It still creates or truncates the file, mode 0644 under the umask.

### Changed

- **macOS is a hard gate.** The `cross-target` job's arm64 macOS leg
  (`macos-14`) ran green on 1.6.1's final commit: the suites, the consumer,
  realmodels, bigfile and the fuzzer. It is no longer `experimental`, so a
  failure there fails CI and the release. x86_64 macOS is still not covered.
  - The leg now runs on `macos-15` (arm64). GitHub retired the macOS 14 image on
    2026-11-02, so a job asking for `macos-14` got no runner ("The
    configuration 'macos-14-arm64-us-default' is not supported").
- **`make bigfile` writes the file back out.** After `tula_read_file_into`, the
  2.36 GB buffer goes through `tula_write_file_atomic`, then `tula_write_file`
  over the copy, and each copy is compared with the buffer word for word. One
  copy is on disk at a time. It adds ~11 s (5.4 s and 5.6 s here), which makes
  the macOS leg the check that both calls handle over INT_MAX bytes.
- **`stream.tcyr`** (+17 assertions): `tula_write_file` and
  `tula_write_file_atomic` against `file_write_all` and `file_write_atomic`.
  - Six sizes from 300,001 bytes down to 0, each replacing a longer file: the
    same bytes and return values.
  - Modes: a new file gets the same mode from both; an existing 0600 file and
    an existing 0666 one keep theirs exactly.
  - A symlinked target is replaced and its target untouched.
  - Writing over a directory fails and leaves nothing behind; so does a missing
    directory, and an over-long path is `-ENAMETOOLONG`.

  Checked by mutation: dropping the mode fix, the `O_TRUNC` or the temp's
  cleanup each fails the suite.
- **The streaming writers' named temp** goes through the same two helpers as
  `tula_write_file_atomic` (create the temp; close, rename and fsync the
  directory). Their behaviour is unchanged.

## [1.6.1] - 2026-11-05

**The write path follow-through.** A patch: no new function, dtype or
convention, and no format change. The streaming writers' output is
**identical** to 1.6.0's (diffed: 300 random builders, 60 of them signed,
written by both).

### Fixed

- **Files over 2 GiB on macOS.** `tula_read_file_into` failed on any file over
  INT_MAX bytes (2 GiB − 1), and the streaming writers failed on any single
  tensor that big (Llama 3.1 405B's BF16 embedding is ~4.2 GB). tula read the
  rest of the file, and wrote each payload, in one request. Linux caps a request
  and returns a short count, which the loops handled. macOS refuses the request
  with EINVAL. Each request is now at most 1 GiB. Found by the new macOS CI leg
  on its first run.
  - Reproduced on Linux with a probe whose reads and writes refuse more than
    INT_MAX bytes, as Darwin's do. There 1.6.0 fails the old `make bigfile`
    exactly as the macOS runner did, at `tula_read_file_into`. 1.6.1 passes,
    never asking for more than 1 GiB.
  - `make bigfile` now holds one 2.2 GB tensor, so the gate covers the write
    side as well. Under the same probe, 1.6.0 and a fix to the read loop alone
    both fail it, at the streaming write.
  - Known limit: `tula_write_file` and `tula_write_file_atomic` hand their
    buffer to the stdlib, whose write loop makes the same single request. On
    macOS they fail with EINVAL (`path` untouched, for the atomic one) on a
    buffer over INT_MAX bytes. That takes a caller's own buffer, or a
    `tula_serialize` result of exactly 2 GiB (the allocation cap). Filed with
    cyrius as `2026-11-05-tula-io-loops-one-request-over-int-max-fails-on-macos.md`.

### Changed

- **Nameless temp files on Linux** (ADR 0006, amended).
  `tula_builder_write_file(_signed)` now builds the file in an `O_TMPFILE` inode
  in the target's directory. While it is written and signed it has no name, so
  no other process can open it. Once it is complete, signed and fsync'd, it is
  linked under a random sibling name (through `/proc/self/fd/N`, or
  `AT_EMPTY_PATH`) and renamed over the target as before.
  - This closes the write-to-sign window ADR 0006 recorded. Before 1.6.1, a
    process with write access to the temp could change the bytes before they
    were signed. Now any change after the file has a name breaks its signature.
  - Where `O_TMPFILE` isn't available (an older kernel, a filesystem without
    it, macOS and the other targets) or `/proc` isn't mounted, the writers use
    the named `O_EXCL` temp of 1.4–1.6.0. Both are checked before anything is
    written, so a fallback never writes the file twice.
  - Mode, symlink and failure behaviour are unchanged, and so is the cost:
    249 ms for 100 MB on either path, and 5.7 s for 1.6.0's 2.42 GB
    `make bigfile` (5.6 s in 1.4.0).
  - `tula_write_file_atomic` (an in-memory buffer, nothing to sign) keeps the
    stdlib's named temp.
- **The streaming writers in the fuzzer** (phase H). 1,500 random builders are
  written, unsigned or signed, through the nameless path or the named temp at
  random. The builders use all three adds, every dtype plus an unknown one, 0–8
  dims, colliding names and long names that share their key prefix, refused
  adds, capped builders, metadata (replaced and refused keys, multi-byte UTF-8),
  and now and then a tensor past the 64 KiB staging buffer.
  - Each file must equal `tula_builder_finish(_signed)` byte for byte.
  - A builder fed only canonical adds must give a file `tula_validate_strict`
    accepts.
  - No temp may be left behind.

  Seven seeded writer bugs were all caught: a shifted big-chunk write, nonzero
  padding, a wrong names record, a wrong metadata offset, a skipped rename, a
  leaked temp and a skipped signature.
- **Cross-target CI.** A new `cross-target` job runs the suites, the consumer,
  `make realmodels`, `make bigfile` and the fuzzer natively on aarch64 Linux
  (`ubuntu-26.04-arm`, a hard gate) and arm64 macOS (`macos-14`, informational
  until its first green run: tula has not run on macOS yet). The `build` job now
  runs the fuzzer too.
  - Locally, the same steps pass on aarch64 under qemu. qemu runs on the host
    kernel, which is why the job uses native runners.
- **`stream.tcyr`** (+17 assertions): the nameless and the forced named-temp
  paths give the same bytes, unsigned and signed, and each leaves only the
  target. Failing writes (a directory at the target, a missing directory) leave
  nothing behind. The late fallback (the file written, then not linkable) was
  checked by mutation: the right bytes, and no stray files.

## [1.6.0] - 2026-11-04

**File metadata.** An additive MINOR with no format change (ADR 0008). A
checkpoint can now carry what it is (architecture, config, provenance), signed
with its tensors. Every 1.5.0 call behaves as before, and output through the
shared API is **identical** to 1.5.0's (diffed: builder bytes, signatures,
strict verdicts, find-name and index answers). In the other direction, **1.5.0
reads 1.6 files**: it opens them, strict-validates and verifies them, resolves
their long names, and sees the metadata as an ordinary int8 tensor.

### Added

- **The metadata table** (ADR 0008): a reserved int8 tensor `__tula.meta__`
  holding sorted, unique key/value text pairs. It sits after every ordinary
  tensor and before the names table (which stays last for 1.3–1.5 readers), and
  the signature covers it.
  - Keys are 1–255 ASCII letters, digits, `.`, `_` or `-`, starting with a
    letter, conventionally `<namespace>.<name>`. The `tula.` prefix is reserved.
  - Values are well-formed UTF-8 text, no NUL, up to 16 MiB.
  - A table holds up to 4,096 pairs and 64 MiB.
- **`tula_builder_set_meta(b, key, value)`** sets or replaces a pair. The table is
  written in key order, so the same pairs give the same bytes whatever order
  they were set in. tula writes no keys of its own.
- **Reading** (`src/meta.cyr`): `tula_meta_count(r)`, `tula_meta_get(r, key)`
  (zero-copy, binary search), and `tula_meta_key(r, i)` / `tula_meta_value(r, i)`
  to iterate in key order. Each record is bounds-checked when read; one that
  doesn't hold up reads as absent.
- **`TULA_ERR_META` (18)**: from the writer for a bad key or value, and from
  `tula_validate_strict` for a non-canonical table. Strict checks the exact
  packing, sorted unique keys, the key charset, UTF-8 values and the caps.
- **ADR 0008** records the design: where the table sits, the caps, key
  namespacing, why values are text-only, and why it isn't folded into the
  names table.

### Changed

- **Layout** (shared by `tula_serialize` and the streaming writer): tensors,
  then the metadata table, then the names table. A builder without metadata
  lays out exactly as before.
- **`tula_builder_add_checked` refuses `__tula.meta__` once metadata is set**
  (`add_long` always does). Without metadata it behaves as in 1.5.0.
- **Reference consumer** sets and reads back metadata. **`make realmodels`**
  gives each of its five inventories three pairs (architecture, a config
  excerpt, a note) and checks them after the signed round trip.
- **Fuzz harness**: every accepted buffer has its metadata walked under the
  guard page. A strict accept must pass a brute-force check: keys strictly
  increasing, `get(key_i) == value_i`, no NUL or never-valid UTF-8 byte. A new
  phase G mutates a canonical file holding metadata and a names table, aiming at
  the metadata.
- **Bench**: `tula_builder_set_meta` ~850 ns and `tula_meta_get` ~430 ns per
  operation, with 64 pairs.
- **Roadmap is future-facing.** The shipped-work list and completed sections are
  gone (history is this file), and the open work is reorganized:
  - **1.6.x**: nameless temp files, writers in the fuzzer, cross-target CI.
  - **1.7.x**: integer and boolean dtypes.
  - **1.8.x**: FP8 and int4. New dtypes are MINOR-only, so each family opens a
    minor line.
  - **1.9.x**: throughput.
  - **1.x.x**: research.
  - **v2**: potential items, each needing an ADR.

  `docs/benchmarks.md` no longer calls the name index a roadmap item, and ADR
  0004 points at the roadmap's v2 section.

### Verified

- Suite **435 → 533** assertions in 12 suites. The new `meta.tcyr` (98) covers:
  - set, replace, get and iterate;
  - order-independent bytes;
  - the key rules and the reserved prefix;
  - UTF-8 classes: overlong, surrogate, past U+10FFFF, stray continuation,
    truncated;
  - the 4,096-pair and 16 MiB caps;
  - the table's position next to a names table;
  - streamed output byte-identical to the in-memory writer, signed and unsigned;
  - the reserved name;
  - the signature covering a value;
  - strict under each kind of tampering;
  - malformed records reading as absent.
- Mutations are caught: an unsorted insert in the builder, surrogates let
  through the UTF-8 check, strict skipping key order.
- `make fuzz`: 2,903,000 iterations, 747,537 accepted buffers, 26,968 strict
  accepts confirmed by brute force, 0 faults, 0 invariant failures.
- `make realmodels`, `make bigfile` and `make example` PASS. `fmt`, `lint`, `vet`
  and `deny` clean. `doc --check` 0 undocumented. `make dist` OK.

## [1.5.0] - 2026-11-04

**Lookup at scale, and real checkpoint inventories.** An additive MINOR with no
format change (ADR 0007). Every 1.4.0 call behaves as before. Output and lookup
answers are **identical** to 1.4.0's: diffed over randomized builders mixing all
three add kinds, covering strict verdicts and `tula_find_name` /
`tula_find_scale` answers for every entry and for 300 random probes.

### Added

- **The name index** (`src/index.cyr`, ADR 0007):
  - `tula_index_new(r)` builds, once per opened buffer, a sorted array of (name
    hash, canonical name) records in one private mapping.
  - `tula_index_find(ix, name)` binary-searches it in O(log n) and returns
    **exactly** `tula_find_name`'s answer: the first matching entry, any length,
    long names confirmed against the names table.
  - `tula_index_find_scale(ix, e, need)` is `tula_find_scale` through the index;
    `tula_index_free(ix)` releases it.
  - It is a sorted array, not a hash table, because the file is untrusted:
    crafted colliding names can't flood it, so build is O(n log n) and lookup
    O(log n) whatever the names. Looking up all 4,096 tensors of a file takes
    3.1 ms through the index, build included, against 44.8 ms by scan (14.5×).
- **`make realmodels`**, a new CI gate. Five real checkpoint inventories, with
  the real tensor names, ranks, counts and dtypes and every dim divided by 64,
  each written signed by the streaming writer, mapped back, strict-validated and
  verified. Every tensor is then resolved through the index **and**
  `tula_find_name` (which must agree), its shape checked, and its payload
  compared byte for byte:
  - GPT-2-small (F32, 148 tensors, names as anukulana's importer reads them);
  - Llama-2-7B (F16, 291);
  - Mixtral-8x7B (BF16, 995, 768 of them long-named experts);
  - a PEFT LoRA adapter (F32, 256, all long);
  - a QLoRA-style NF4 import of Llama-2-7B (517, with `.scale` sidecars found
    through `tula_index_find_scale`).
- **ADR 0007** records the index design.

### Changed

- **Shared helpers for lookups**: `tula_find_name`, `tula_find_scale` and the
  index confirm a candidate and check a scale sidecar through the same code, so
  they can't disagree. The strict validator's heapsort gained a tiebreak flag:
  strict keeps equal names equal, and the index orders them by entry, giving
  first-match semantics.
- **Fuzz harness**: every accepted buffer (500,973 per run) gets an index under
  the guard page, and `tula_index_find` must equal `tula_find_name` on each
  entry's full name, stored name, and a long probe. A run now takes 41 s
  (was 24 s).
- **Bench**: index build, short and long index lookups, and a 4,096-tensor
  find-everything comparison.

### Not in tula

- **The real-*weights* round trip** (roadmap 1.5.x) belongs to anukulana. Its
  `gpt2-tula` demo already imports the real GPT-2 safetensors, NF4-quantizes it,
  saves a signed tula checkpoint, reloads it and checks the result bit for bit.
  It runs on tula 1.0.1 and cyrius 6.6.2, and needs the 500 MB checkpoint
  staged. Pulling anukulana into tula's CI would make tula depend on its own
  consumer, so `make realmodels` covers the tula side (real inventories, through
  every 1.2–1.5 path) and the roadmap lists anukulana's migration.

### Verified

- Suite **422 → 435** assertions in 11 suites. The new `index.cyr` checks
  equivalence with `tula_find_name` and `tula_find_scale` over 40 random files
  with duplicates and names tables, foreign-style name fields with bytes after
  the NUL, an empty file, and 1,000 tensors (half long-named) on an mmap'd file.
- Mutations are caught: dropping the tiebreak breaks first-match on duplicates,
  and non-canonical keys break the foreign-field cases.
- `make fuzz`, `make realmodels`, `make bigfile` and `make example` all PASS.
- `fmt`, `lint`, `vet` and `deny` clean. `doc --check` 0 undocumented.
  `make dist` OK.

## [1.4.0] - 2026-11-04

**Big files.** An additive MINOR with no format change (ADR 0006). Checkpoints
of any size up to the 1 TiB read cap can now be written, signed, replaced
atomically and read on the heap. That closes audit D-3, D-8 and D-9. Every 1.3.0
call behaves as before, and in-memory output is **byte-identical** to 1.3.0's
(diffed: random builders mixing all three add kinds, names tables, signatures,
strict verdicts, the F16/BF16/F32 conversions).

### Added

- **`tula_builder_write_file(b, path)`** streams the builder's file to disk
  without ever holding it. The header, manifest and names table go through a
  64 KiB staging buffer (a private mapping); each payload is written straight from
  the caller's buffer. It writes exactly the bytes `tula_builder_finish` returns,
  with no 2 GiB cap.
- **`tula_builder_write_file_signed(b, path, sk)`** does the same, Ed25519-signed,
  and is byte-identical to `tula_builder_finish_signed`. It writes the content,
  maps it back read-only, signs the mapping, and appends the signature.
  `ed25519_sign` streams its message through SHA-512 without a copy, so **no new
  sigil API was needed**. The roadmap's multi-part-sign request is dropped.
- **Atomic replace for both streaming writers.** Each writes a sibling temp
  `<path>.tula-<16 hex>.tmp`:
  - created with `O_CREAT|O_EXCL`, so a planted name is never opened and another
    name is tried;
  - named with 64 random bits from `getrandom`;
  - given the existing target's mode, so it is never more permissive than the
    result.

  The writer then fsyncs and renames it over `path`, and fsyncs the directory. On
  any failure the temp is removed and `path` is untouched. A symlink at `path` is
  replaced, not written through.
- **`tula_write_file_atomic(path, buf, len)`**: the same guarantee for an
  in-memory buffer (the stdlib's `file_write_atomic`).
- **`tula_file_len(path)`** returns the total a file declares, once the file is
  known to hold it. **`tula_read_file_into(path, buf, cap)`** reads into the
  caller's buffer, which can be reused and can be larger than 2 GiB, so heap reads
  work for any file size and leave no buffer stuck in the bump allocator.
- **`make bigfile`**, a new CI gate: a 2.42 GB checkpoint (36 × 64 MiB tensors,
  short and LoRA-length names) is refused by the in-memory path, streamed in
  5.6 s, mapped, strict-validated, spot-checked by full name, refused by
  `tula_read_file`, and read through `tula_read_file_into`. **`make
  bigfile-signed`** does the same signed and verified (locally; see below).
- **ADR 0006** records the design.

### Changed

- **`tula_serialize`** and the streaming writer share one layout calculation,
  header writer and names-table entry writer, so they can't drift apart.
- **Bench**: a streaming-write op: 100 MB in 289 ms (363 MB/s) including fsync.

### Notes

- **Signing big files is bound by sigil's SHA-512**, measured at ~18 MB/s.
  Ed25519 hashes the message twice to sign and once to verify. For 2.42 GB:
  sign 266–274 s, verify 127–129 s (two runs). A 14 GB checkpoint would take about 25 minutes to
  sign. tula adds only the write and one mapping. Crypto is sigil's (ADR 0001),
  so this is now a cross-repo ask on the roadmap. It is why the signed big-file
  gate runs locally rather than in CI.

### Verified

- Suite **388 → 422** assertions in 10 suites. The new `stream.tcyr` (34)
  checks:
  - **Streamed equals in-memory, byte for byte**, unsigned and signed, over 12
    randomized builders: long names, empty and 0-dim tensors, a payload larger
    than the staging buffer.
  - **Atomic replace**: the old file is kept when the target directory is missing
    or the target is a directory, and no temp file is left behind.
  - **Mode and symlinks**: a 0600 target stays 0600, and a symlinked target is
    replaced while the link's target is untouched.
  - **Reading**: `tula_file_len` and `tula_read_file_into` (exact and short
    buffers, reuse across files, truncated files).
- Mutations are caught: dropping the payload padding breaks byte equality, and
  skipping the temp cleanup leaves a file the test sees.
- `make bigfile` PASS. `make bigfile-signed` PASS (2,415,925,104 bytes, signed
  and verified). `make fuzz` PASS (0 faults, 0 invariant failures).
- `fmt`, `lint`, `vet` and `deny` clean. `doc --check` 0 undocumented.
  `make example` PASS. `make dist` OK.

## [1.3.0] - 2026-11-04

**Real names, real dtypes.** An additive MINOR with no format bump: two new
conventions inside format v1, each recorded in an ADR. It closes audit D-1 (long
names, properly) and D-10 (F32/F16/BF16). Every 1.2.0 call behaves as before,
and the plain and checked builders' output is **byte-identical** to 1.2.0's
(diffed over randomized builders, with NF4 and int8 outputs too).

### Added

- **Long tensor names** (ADR 0004). `tula_builder_add_long` takes names of any
  length. A name of 47 chars or fewer is added exactly as with `add_checked`. A
  longer one is stored whole in a **names table**: the reserved int8 tensor
  `__tula.names__`, appended as the last entry. Its entry holds a 47-byte
  **key**: the first 30 bytes, `~`, then FNV-1a-64 in hex.
  - `tula_find_name(r, name)` looks up by full name and **verifies it** against
    the table, so a hash collision can't return the wrong tensor.
  - `tula_entry_full_name(r, e)` returns the name; `tula_has_long_names(r)` says
    whether a table is present.
  - **The acceptance test passes:** the LoRA pair `…q_proj.lora_A.weight` /
    `…lora_B.weight` (62 chars, the same first 47 bytes) round-trips as two
    distinct tensors. So does Mixtral's 51-char
    `model.layers.0.block_sparse_moe.experts.0.w1.weight`.
  - **Every 1.x reader opens these files.** 1.0–1.2 see the keys as names and
    the table as an ordinary int8 tensor, and 1.2's strict validator accepts them.
- **`TULA_DT_F32` (4), `TULA_DT_F16` (5), `TULA_DT_BF16` (6)** (ADR 0005), with
  IEEE 754 conversions to and from f64: `tula_f64_to_f32/f16/bf16`,
  `tula_f32/f16/bf16_to_f64`, and array `tula_f32/f16/bf16_pack` / `_unpack`.
  - Round to nearest, ties to even, straight from the f64. BF16 is never rounded
    through F32: 1 + 2⁻⁸ + 2⁻³⁰ is `0x3F81` directly, `0x3F80` via F32.
  - ±inf on overflow, correctly rounded subnormals (no flush to zero), signed
    zeros kept, NaN quiet with its sign and payload.
  - Integer arithmetic only, so a file's bytes never depend on the writer's FP
    mode.
  - `tula_packed_len`, `tula_entry_payload_ok` and `tula_validate_strict` learn
    the sizes.
- **`TULA_ERR_NAMES` (17)** — `tula_validate_strict` requires a names table to be
  canonical: ordered records, names packed in order, each over 47 bytes with no
  embedded NUL, and each entry's field equal to its name's key.
- **ADRs** 0004 (long names) and 0005 (the dtypes and their rounding).
- New module `src/names.cyr` (the table reader).

### Changed

- **`tula_find_scale` uses the entry's full name**, so a long-named tensor's
  `"<full name>.scale"` sidecar is found through the table. A file without long
  names has no such sidecar, so 1.2.0's answers are unchanged.
- **`tula_builder_add_checked` refuses `__tula.names__` once the builder holds a
  long name**, because the table will take that name. Without long names it
  behaves exactly as in 1.2.0.
- **Builder** (private layout): it records long names. It reserves the table's
  manifest slot and its bytes under the size cap. The checked add costs 192 → 213
  ns for that bookkeeping.
- **Reference consumer** (`examples/consumer.cyr`, the CI gate) also writes a
  62-char LoRA tensor in BF16 with `add_long` and loads it back with
  `tula_find_name` + `tula_bf16_unpack`.
- **Fuzz harness**:
  - Every accepted buffer runs `tula_entry_full_name` on every entry, with the
    result scanned to its NUL under the guard page.
  - When the strict validator accepts, `tula_find_name(full_name(e)) == e` must
    hold for every entry.
  - The consumer phase unpacks F32/F16/BF16.
  - New phase F mutates a canonical long-name file, aiming at the names table.
- **Bench**: F32/F16/BF16 pack (~100–109 Melem/s) and unpack (~138 Melem/s) on
  2²⁰ elements, and long-name add (~0.7 µs) and lookup (~2.1 µs, 256 LoRA names).
  The array conversions take an inline fast path for normal numbers, about 2.2×
  the scalar path, bit-identical (tested).

### Fixed (during development)

- The F32 oracle test caught widening keeping a **signaling** NaN signaling. It
  disagreed with `cvtss2sd` on 572 of 300,000 random f32 codes, exactly the
  signaling-NaN share. IEEE 754 never returns a signaling NaN from a conversion,
  so widening now sets the quiet bit (ADR 0005 updated).

### Verified

- Suite **274 → 388** assertions in 9 suites: new `floats.tcyr` (37) and
  `names.tcyr` (77).
  - **F16 and BF16 exhaustively:** all 65,536 codes round-trip, and every
    neighbour midpoint (and ±1 f64 ulp) rounds correctly at both signs.
  - **F32 matches the hardware** on 300k random inputs plus specials, and 100k
    midpoints.
  - **BF16 matches the classic F32-bit rounding** on 300k F32-exact inputs.
  - **The array fast paths match the scalar path** on every 16-bit code and
    midpoint, and on 300k F32 cases.
  - **Mutations are caught:** ties-up, a dropped carry and an off-by-one
    subnormal shift in the conversions, and in names, `tula_find_name` trusting
    the key or strict skipping the key check.
- `make fuzz`: 2,603,000 iterations, 2.1M entries unpacked, 14,455 strict accepts
  all passing the find-name round trip, 0 faults, 0 invariant failures.
- `fmt`, `lint`, `vet` and `deny` clean. `doc --check` 0 undocumented.
  `make example` PASS. `make dist` OK.

## [1.2.0] - 2026-11-04

**Real checkpoints, checked.** An additive MINOR (ADR 0003): new functions and
error codes only. Every 1.1.2 call behaves as before, the on-disk format is
v1 unchanged, and the plain builder's output is **byte-identical** to 1.1.2's
(diffed over randomized builders). This is the roadmap's 1.2.0 milestone; its
items close audit D-1 (short term), D-2, D-4, D-5, D-6 and D-11
([2026-11-04 audit](docs/audit/2026-11-04-audit.md) §5).

### Added

- **`tula_builder_new_cap(max)`** — a builder for up to `max` tensors (1 ..
  `TULA_READ_MAX_TENSORS`). `tula_builder_new` keeps the frozen default of 256,
  which real models pass (Llama-2-7B has 291 tensors).
- **`tula_builder_add_checked(...)`** — the add that refuses what the plain one
  silently accepts: a name over 47 chars (`TULA_ERR_NAME_LONG`, instead of
  truncating it) and a name already in the builder (`TULA_ERR_DUP_NAME`). That
  includes a plain add's truncated name, so the LoRA `lora_A` / `lora_B`
  collision can no longer be written. It is O(1) per add, through a name index in
  the builder.
- **`tula_validate_strict(buf, len)`** — new module `src/check.cyr`. It accepts a
  buffer only if it is **canonical**: exactly what a correct tula writer
  produces. That means no overlapping tensors, no gaps or reordering, 8-aligned
  offsets, zero padding and zero name bytes after the NUL, an exact total length,
  known dtypes, zero dims past `ndim`, `data_len` equal to the dtype's packed
  length for the shape, and unique names. Careful safetensors readers enforce the
  same family of rules. Duplicates are found by a heapsort of (name hash, entry)
  records, worst case O(n log n) whatever the names; untrusted names never go
  into a hash table, so crafted collisions can't make the check quadratic.
- **`tula_verify_required(r, pk)`** → `TULA_OK` / `TULA_ERR_UNSIGNED` /
  `TULA_ERR_SIG`. A stripped signature (a valid unsigned file) is rejected in one
  call.
- **`tula_find_scale(r, e, need)`** — an entry's `"<name>.scale"` sidecar, checked
  for an unpack that reads `need` scales (exists, f64, `payload_ok`, at least
  `need` elements in at least `need * 8` bytes). It replaces the hand-written
  sidecar checks.
- **`tula_entry_nelems(e)`** — element count, overflow-safe. It is 1 for a 0-dim
  entry (a scalar), 0 for an empty tensor, and −1 for a negative dim or a product
  over the cap.
- **Error codes** `TULA_ERR_DUP_NAME` (13), `TULA_ERR_LAYOUT` (14),
  `TULA_ERR_SHAPE` (15) and `TULA_ERR_DTYPE` (16), with names in `tula_err_name`.

### Changed

- **The builder copies the name and shape at add time.** Before, it borrowed both
  pointers until `finish`, so reusing one shape buffer across adds gave every
  tensor the last shape. `data` is still borrowed until `finish`. Internally each
  builder entry is now the ready-made 144-byte manifest entry, so serialize is a
  straight copy. The builder layout is private.
- **`tula_builder_new` returns 0 if its allocation fails** (it used to return an
  unusable pointer).
- `tula_err_name(TULA_ERR_TOO_MANY)` now reads "too many tensors (builder or
  reader cap)": the reader returns it too.
- **Reference consumer** (`examples/consumer.cyr`, a CI gate) writes through the
  checked add and loads through `tula_validate_strict` → `tula_verify_required`
  → `tula_find_scale`.
- **Fuzz harness.** Its PRNG returned raw power-of-two LCG state, whose low bits
  have tiny periods, so every `rng_below(s, small)` choice (mutation kind, offset,
  value class) followed a short fixed pattern. Outputs now pass through the
  splitmix64 finalizer, and accepted buffers rose 230k → 268k on the same
  iteration count. The strict validator runs on every accepted buffer, and when
  it accepts, a brute-force check must agree. A new phase fuzzes a 40-tensor
  canonical file (past the pairwise threshold, so the heapsort runs) with
  duplicate names injected.
- **Bench**: strict validate (200 tensors: 42 µs; 256 long names: 77 µs) and
  plain vs checked add (171 vs 192 ns per add).

### Verified

- Suite **178 → 274** assertions in 7 suites. New: `strict.tcyr` (67), plus 29
  more in `builder.tcyr` for the sized builder, the checked add, and copy-at-add.
- Mutations of the strict validator turn the suite red: skipping the sort,
  dropping the padding check, allowing gaps. The last needed a new case, a gap
  and an overlap that cancel, which only the cursor rule catches.
- `make fuzz`: 2,303,000 iterations, 6,302 strict accepts all confirmed by brute
  force, 147,167 duplicate-name verdicts, 0 faults, 0 invariant failures.
- `fmt`, `lint`, `vet` and `deny` clean. `doc --check` 0 undocumented.
  `make example` PASS. `make dist` OK (no stdlib sidecar needed).
  `deps --verify` 60/60.

## [1.1.2] - 2026-11-04

A P(-1) pass: hardening, optimization and repair. Report:
[`docs/audit/2026-11-04-audit.md`](docs/audit/2026-11-04-audit.md). No API
addition and no format change. Every valid input gives the same result as 1.1.1;
files and dtype outputs are **byte-identical** to 1.1.1's (diffed). Ten defects
were reproduced on 1.1.1 and fixed. Toolchain and deps unchanged (cyrius 6.7.18,
sigil 3.13.15).

### Fixed

- **`tula_open_mmap` crashed on a truncated file (High).** A file shorter than its
  header's total was mapped and passed validation, which checked the header's own
  length. The first read of the missing tail raised SIGBUS. Both readers now
  compare the declared total with the file's real size before mapping or
  allocating, and reject a shorter file.
- **`tula_open_mmap` leaked a mapping for every file it rejected.** 500 rejected
  opens left 500 mappings. With Linux's ~65k-map ceiling, and `alloc` itself
  mapping memory, enough hostile files would make allocation fail. It now unmaps.
- **`tula_read_file` allocated what the header claimed, not what the file held.**
  A 64-byte file claiming 256 MiB reserved 256 MiB+ that is never released
  (8 reads: +4 GiB address space). It now allocates only after the size check, and
  reads header and body through one `open` (it opened the path twice).
- **`tula_builder_add` accepted arguments that corrupted or broke the file.** A
  negative `data_len` moved the next tensor to offset −88, over the manifest. An
  `ndim` outside 0..8, or a payload over `TULA_READ_MAX_BYTES`, wrote a file
  tula's own reader rejects. These now return `TULA_ERR_BOUNDS`, `TULA_ERR_NDIM`
  or `TULA_ERR_TOO_BIG` and leave the builder unchanged.
- **`tula_builder_finish` / `_signed` crashed when the allocation failed** (any
  builder over the stdlib's 2 GiB per-allocation cap). They return 0.
- **NF4 helpers divided by zero for `block <= 0`.** `tula_nf4_blocks`, `_pack` and
  `_unpack` now return 0 and write nothing.
- **`tula_entry_payload_ok` broke its own contract.** Shape `[0, -5]` returned 1,
  although a negative dim must return 0. `[2^30, 2^30, 0]` (an empty tensor)
  returned 0. Every dim's sign is now checked first, and any zero dim means empty.
- **`tula_close_mmap(0)` segfaulted.** It is now a no-op.
- **`tula_serialize` left alignment padding and the reserved signature block
  unwritten.** Not reachable with the stdlib allocator, which zeroes memory before
  reuse, but the file bytes depended on it. They are now written as zero.
- **The reference consumer** (`examples/consumer.cyr`, the v1.0 CI gate) went on
  after a failed check and then read what the check guarded. It now rejects on
  each failure, guards the scale and bias tensors with `tula_entry_payload_ok`,
  and checks rank, dims and dtype before they size anything.

### Changed

- **Faster, same bytes.** These are all measured on the same machine, and outputs
  are diffed byte-for-byte against 1.1.1.
  - serialize: 591 → 4,036 MB/s (word copy instead of the stdlib's byte-loop `memcpy`).
  - `tula_find`: 11.6× on 256 long names (the query is measured once, a longer
    one is rejected up front, and names are compared a 64-bit word at a time).
  - NF4 pack: 3.9×. NF4 unpack: 3.0×. Ternary unpack: 2.4×. int8 dequant: 1.2×.
- **Behaviour at the edges.** These cases used to crash, corrupt or silently
  succeed; none affects a valid input.
  - `tula_builder_add` has three more error returns (above).
  - `tula_builder_finish` / `_signed` can return 0.
  - The NF4 helpers return 0 for `block <= 0`.
  - `tula_read_file` and `tula_open_mmap` reject a source they can't size with
    `lseek`, e.g. a pipe. `mmap` never worked on one.
  - A file *longer* than its header's total still opens, as before.
- **Tests and the example write under `build/`**, not fixed `/tmp` names (a
  planted symlink there is followed by `O_TRUNC`). `make test` creates `build/`.
- **Fuzz harness**: every buffer under test now ends at a `PROT_NONE` guard page,
  so an over-read faults instead of passing an arithmetic check. A new phase runs
  `tula_entry_payload_ok` and then each dtype's unpack on every accepted entry.
- **Bench** widened (serialize, validate, find, dtype pack/unpack) and switched to
  µs resolution. Its file now lives in `build/`.
- **Docs.** All public accessors now have doc comments (`cyrius doc --check`: 8
  undocumented → 0). `SECURITY.md`, `docs/api.md` and the guide now cover the
  real-size check, the mmap concurrent-writer caveat, and long-name collisions.
  The roadmap is reorganized into 1.2.x – 1.x.x milestones.

### Verified

- Suite **105 → 178** assertions in 6 suites (new `builder.tcyr`; `fileio` and
  `dtype` extended with regression tests and differential tests against the 1.1.1
  code). Mutations to the new code turn the suites red (one equivalent mutant
  noted in the report).
- `make fuzz`: 2,003,000 iterations under the guard page, 40,472 entries unpacked,
  0 faults, 0 invariant failures.
- `fmt`, `lint`, `vet` and `deny` clean. `doc --check` 0 undocumented.
  `make example` PASS. `make dist` OK. `deps --verify` 60/60.

## [1.1.1] - 2026-11-04

### Changed

- **Toolchain `6.7.9` → `6.7.18`.** No source change; nothing in the 6.7.10–6.7.18 migration
  notes touches tula's Linux code paths. `lib/` re-resolved by `cyrius deps` from the 6.7.18
  snapshot (`deps --verify` 60/60). The snapshot now carries `lib/unicode/`, see Binary below.
- **Deps at their latest releases.** sigil **3.13.15** is still sigil's newest tag on GitHub, so
  `[deps.sigil]` doesn't move. It's now also exactly the copy the 6.7.18 toolchain bundles, so
  1.1.0's `./lib/ shadows version-pinned … sigil` build warning is gone.
- **Local `cyrius.lock` regenerated.** It still held a sigil 3.13.10 commit pin beside 3.13.15's
  (left by the 1.0.3 resolve), which 6.7.18 reports as `cyrius.lock keeps sigil@3.13.10's pin …
  fail-closed`. Deleting and re-resolving leaves one pin, 3.13.15 at `3c47656`. The lock is
  gitignored, so other checkouts and CI never saw it. If you have a lock from before 1.1.1 and
  see that note, delete it.

### Binary

- **Smoke binary 251,280 → 590,952 B**, all of it data. The code segment is ~100 KB; the RW
  segment grew to 488 KB. bayan 1.9.0, folded into cyrius 6.7.13, made `lib/bayan.cyr` require
  `lib/unicode/` (~300 KB of string tables). DCE removes functions, not global initializers, so
  the tables stay in any binary that includes bayan. tula's own code makes no bayan calls: it
  arrives through `dist/sigil.cyr`'s `# Requires` block. So the fix is sigil's, tracked in sigil's
  open issue `2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md`. kybernet, libro and
  argonaut recorded the same jump. Consumers of `dist/tula.cyr` already pay it through sigil.

### Verified

- Suite **105/105** (5 suites). Builds and tests warning-free. Lint, fmt and vet clean.
  `make example` PASS. `make fuzz` 2,003,000 iterations, 0 invariant failures. `make bench` and
  `make dist` OK (`dist/tula.cyr` changes only in its version lines).

## [1.1.0] - 2026-11-04

No API addition and no format change. The public surface and on-disk format v1 are
exactly 1.0.3's. The minor bump marks the move to the 6.7 toolchain line and git-first
dependency resolution.

### Changed

- **Toolchain `6.6.20` → `6.7.9`.** No source change. `lib/` re-resolved by `cyrius deps` from the
  6.7.9 snapshot (52 files, `deps --verify` clean).
- **`[deps.sigil]` tag `3.13.10` → `3.13.15`**, the sigil release that pins 6.7.9 (and sigil's
  latest). It's also what libro, kavach, daimon and the other sigil consumers on 6.7.18 pin.
  3.13.11–3.13.15 are additive-only for API (one new `x509_name_constraints_check_ca`), and
  tula's Ed25519 calls are unchanged. sigil's stdlib sidecar is identical to 3.13.10's, so
  `[deps].stdlib` doesn't move.
- **Smoke binary 516,656 → 251,280 B.** sigil 3.13.12 shrank a 256 KB static buffer to 4 KB, so
  the `array local … gets STATIC storage` and `large static data` build warnings are gone.
- **Git first (cyrius ≥ 6.7.6).** Every build now resolves the sigil tag, a dev box's included.
  `path = "../sigil"` is read only in local mode (`CYRIUS_LOCAL=1` / `--local`), which builds
  under `build/local-deps/` and leaves `lib/` + `cyrius.lock` untouched. The comments in
  `cyrius.cyml` and `ci.yml`, plus `getting-started.md`, `state.md` and the roadmap's sigil
  bullet, now say so. The roadmap's 6.7.6 to-do is marked applied. Its `cyrius deps --locked`
  item doesn't apply: tula's CI has no lock guard and `cyrius.lock` stays gitignored.

### Notes

- Builds print `./lib/ shadows version-pinned …/versions/6.7.9/lib … sigil 3.13.15 (pinned:
  3.13.11)`. The 6.7.9 toolchain ships its own sigil copy from before 3.13.12. The declared
  `[deps.sigil]` tag is what `lib/` holds and what CI builds. The `cyrius lib sync --full`
  the warning suggests is refused here (lock and snapshot disagree) and isn't needed.
  `CYRIUS_NO_WARN_SHADOW_LIB=1` silences it.

### Verified

- Suite **105/105** (5 suites). Lint, fmt and vet clean. `make example` PASS. `make fuzz`
  2,003,000 iterations, 0 invariant failures. `make bench` and `make dist` OK
  (`dist/tula.cyr` changes only in its version lines). Local mode checked too: it builds
  `../sigil` from `build/local-deps/` with `lib/` and `cyrius.lock` byte-identical afterwards.

## [1.0.3] - 2026-11-04

### Changed

- **Toolchain `6.6.2` → `6.6.20`.** No source change. `lib/` re-resolved by `cyrius deps` from the
  6.6.20 snapshot (52 files, `deps --verify` clean).
- **`[deps.sigil]` tag `3.12.16` → `3.13.10`**, the last sigil tag pinned within 6.6.x (it pins
  6.6.18; 3.13.11 moves to 6.7.5). It's the same sigil `ifran` pins at 6.6.20. tula's Ed25519 calls
  (`ed25519_keypair` / `_sign` / `_verify`) are unchanged across the range.
- **`[deps].stdlib` gains `sys`.** sigil 3.13.10's `dist/sigil.deps` lists it. The leaves sigil's
  sidecar dropped at 3.13.10 (`assert`, `bench`, `fnptr`, `fs`, `result`, `str`) were already in
  tula's own list, so nothing else moves.
- **`dist/tula.deps` removed by `cyrius distlib`.** Since 6.6.18 the sidecar lists only the leaves
  its compile check proves the bundle needs. Every leaf `dist/tula.cyr` reaches comes in through
  sigil's sidecar, which consumers already resolve because they supply `ed25519_*`. With nothing
  left to list, distlib deletes the file (`sidecar: removed dist/tula.deps (no stdlib leaves
  remain)`). `dist/tula.cyr` changes only in its version lines.

### Verified

- Verified against the **tagged** sigil, the graph CI builds. `path = "../sigil"` still wins under
  6.6.20 (git-first only arrives in 6.7.6), and the sibling checkout is at 3.13.15, which pins
  6.7.9. So the run was done with the override dropped. Suite **105/105** (5 suites). Lint, fmt and
  vet clean. `make example` PASS. `make fuzz` 2,003,000 iterations, 0 invariant failures.
  `make bench` and `make dist` OK.

## [1.0.2] - 2026-09-11

### Changed

- **Toolchain `6.5.27` → `6.6.2`.** No source change; the value form needed none.
  Build, tests, and any bench/fuzz/distlib target the repo ships re-verified at the new pin.


## [1.0.1] — 2026-08-17

### Changed

- **Cyrius pin `6.3.27` -> `6.5.27`** (2026-08-17, ecosystem-wide ML/AI-arc realign ahead of
  the arc reopening). `cyrius lib sync --full` re-vendored the whole version-matched stdlib
  snapshot.
- **`[deps.sigil]` tag `3.9.9` -> `3.12.9`.** The declared tag was three minors behind while a
  `path = "../sigil"` override meant local dev and the 105-assertion suite had been resolving
  the *working copy* all along — so the tag was never exercised and CI was the only thing that
  would ever have built the declared graph ([[reference_path_override_disables_the_tag_as_a_test]]).
  Aligning it makes CI build what dev has been testing. Vendored `lib/sigil.cyr` confirmed at
  `# Version: 3.12.9`; suite **105/105**, unchanged.

### Fixed

- **The suite was `0 passed / 5 failed` at the old pin — every file a compile error — and the
  bump is what made it green (5/5, 105 assertions).** The vendored `lib/sigil.cyr` calls
  `thread_local_alloc`, which the stdlib only gained at cyrius **v6.4.65**; tula's pin was
  6.3.27, so `lib/thread_local.cyr` was a snapshot that predates the function and every test
  binary died on `refusing to emit binary with 1 reachable undefined function(s)`. Nothing in
  tula's own source was wrong — this is the stale-vendored-stdlib trap, and re-syncing at the
  new pin is the whole fix. The frozen v1 format and the public API are untouched.

## [1.0.0] — 2026-07-01

**v1.0 — API freeze.** The codec surface is frozen (`docs/api.md` +
`STABILITY.md`); the on-disk format is **v1**. The march from 0.1.0: file I/O,
dtype payload helpers, reader hardening (the untrusted-input trust gate), fuzz +
bench, and a security audit — with a green end-to-end downstream consumer.

### Added
- **First-party documentation scaffold** (per the AGNOS first-party doc standard).
  Root files completed: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (all seven required
  root files now present). `docs/` filled to the standard: `docs/guides/`
  (`README.md` + `getting-started.md`), `docs/architecture/` (`README.md` +
  `001-flat-module-layout.md` + `002-accessors-require-validated-buffer.md`),
  `docs/examples/README.md` (indexes the root `examples/`),
  [ADR 0003](docs/adr/0003-api-freeze-at-v1.md) recording the 1.0 API + format-v1
  freeze decision, and `docs/sources.md` citing the quantization schemes (NF4 →
  QLoRA/bitsandbytes, ternary → BitNet b1.58, int8 → LLM.int8(), Ed25519 → RFC
  8032) with an inline citation on `tula_nf4_level`. `CLAUDE.md` de-staled: a
  durable pointer block (→ `state.md` / `CHANGELOG` / `api.md`) + a docs pointer
  replace the old inline roadmap/version.
- **v1.0 prep — freeze docs + downstream consumer.** `docs/api.md` documents the
  frozen public surface (format spec, builder, reader, sign, file-I/O, dtype
  helpers, error/dtype/sig constants). `STABILITY.md` states the post-1.0 policy
  (format v1 frozen; MINOR = additive-only; MAJOR = format/API break; internal
  helpers + cap values excluded). `examples/consumer.cyr` (`make example`) — a
  complete end-to-end consumer: ternary-quantize → build + scale sidecar → sign →
  write → read (untrusted) → verify → `tula_entry_payload_ok` guard → unpack →
  dequant, plus a bit-exact f64 tensor; runs green and is a **CI gate**. CI lint
  + fmt-check now also cover `examples/`.
- **M5 — security audit + `SECURITY.md`**. Six-dimension audit
  (`docs/audit/2026-07-01-audit.md`): memory safety · integer overflow ·
  untrusted-input bounds · signature-verify correctness (sigil canonical-`S`
  reject + `ct_eq` compare) · resource caps · fail-loud — **verdict PASS**. One
  consumer-side over-read sharp edge (a lying `shape` vs a smaller `data_len`)
  found and **closed**: new `tula_packed_len(dtype, nelems)` +
  `tula_entry_payload_ok(e)` (`src/dtype.cyr`) — an overflow-safe one-line guard a
  foreign-checkpoint consumer runs before any unpack. `SECURITY.md` documents the
  threat model (reader = trust boundary; signed header = authenticity boundary via
  sigil; keys are the caller's; writer is trusted). `dtype.tcyr` +8 (now 29).
  Suite total now **105**.
- **M4 — fuzz + bench harnesses**. `programs/fuzz.cyr` (`make fuzz`): a
  deterministic-LCG fuzzer that floods `tula_open` + every accessor + `tula_verify`
  with mutated + random bytes — **2,003,000 iterations** (>10⁶) clean, asserting
  no crash and that every *accepted* buffer is genuinely sound (re-validation
  agrees; every entry's payload range stays inside `[buf, buf+len)`). Validates
  the M3 hardening. `programs/bench.cyr` (`make bench`): write/read/mmap
  throughput on a ~100 MB synthetic file (200 tensors); numbers + method in
  `docs/benchmarks.md`. `make fuzz` / `make bench` targets added.
- **M3 — reader hardening** (`src/format.cyr`): `tula_validate(buf, len)` — the
  untrusted-input trust gate. Validates every structural invariant against the
  buffer length (magic/version, `manifest_off == 64`, `payload_off == 64 +
  count*ENTRY_SIZE ≤ len`, `payload_off+payload_len ≤ len`, per-entry `ndim ≤ 8`,
  NUL-terminated names, `data_off+data_len ≤ payload_len`, sig-field consistency)
  with overflow-safe arithmetic, and rejects with a specific `TULA_ERR_*` code.
  **`tula_open` now runs full validation** (was magic+version only), so untrusted
  files can never OOB-deref. `sig_len` is pinned to {0, 64} so `tula_verify`'s
  fixed 64-byte read can never escape the buffer. Resource caps
  (`TULA_READ_MAX_TENSORS` = 2²⁰, `TULA_READ_MAX_BYTES` = 2⁴⁰) bound arithmetic
  and guard against bomb-sized headers; `tula_read_file`/`tula_open_mmap`
  sanity-check the header total (`tula_hdr_total`) **before** allocating/mmap'ing.
- New error codes: `TULA_ERR_BOUNDS` (9), `TULA_ERR_NDIM` (10), `TULA_ERR_HEADER`
  (11), `TULA_ERR_TOO_BIG` (12), with names in `tula_err_name`.
- `tests/tcyr/hardening.tcyr` (**30 assertions**): bad magic/version, len<header,
  truncated payload, over-/negative-count, payload-len bomb, lying + overflowing
  entry offsets, out-of-range ndim, unterminated name, sig-field inconsistency
  (wrong offset / non-{0,64} length / cut-short signature), and pure-garbage —
  all rejected with the right code, no crash. Existing suites stay green under the
  stricter `tula_open`. Suite total now **97**.
- **M2 — dtype payload helpers** (`src/dtype.cyr`): pure pack/unpack transforms
  for the quantized dtypes. **Ternary** {−1,0,+1} ↔ 2-bit packed codes
  (`tula_ternary_pack`/`_unpack`/`_get`/`_bytes`; mirrors tentib's `tpack2`).
  **int8** per-tensor absmax (`tula_int8_quant` returns the f64 scale /
  `tula_int8_dequant`). **NF4** 4-bit blockwise NormalFloat (`tula_nf4_pack`/
  `_unpack`/`_get`/`_nearest`/`_level`/`_blocks`/`_bytes`; the 16-entry QLoRA
  codebook as f64 bit patterns, per-block absmax scales, div-by-zero-safe
  zero-blocks). Double-quant composes for free (int8-quantize the scale sidecar).
- **ADR 0002** — quantization **scales are sidecar `"<name>.scale"` tensors**,
  not an entry field: no `TULA_VERSION`/`TULA_ENTRY_SIZE` bump (the 144B entry
  stays frozen), scales stay first-class introspectable f64 tensors whose shape
  expresses granularity (scalar / per-row / per-block). Rejected option (a) —
  a single entry field can't hold NF4's per-block scale *array*.
- `tests/tcyr/dtype.tcyr` (**21 assertions**): ternary exact round-trip +
  accessor agreement, int8 within-a-quantum + signed-rail, NF4 within
  half-gap·absmax over two distinct-scale blocks, zero-block safety, and a full
  build→write→read of a ternary tensor **+ its `.scale` sidecar**. Suite total
  now **67**.
- **M1 — file I/O** (`src/fileio.cyr`): `tula_write_file` (serialize→disk),
  `tula_read_file` (read back into a heap buffer; validates magic/version),
  `tula_open_mmap` (zero-copy read-only mmap) + `tula_close_mmap`. tula files are
  self-describing (the header carries the total length), so reads need no `stat()`.
- `tests/tcyr/fileio.tcyr` (**16 assertions**): write→read bit-identical, signed
  file survives + verifies, mmap round-trip, missing-file → 0. Suite total now **46**.

## [0.1.0] — 2026-07-01

**M0 + M0b — the weight-file format, round-trip, and the sigil-signed header.**
First cut of the sovereign weight-file format with an Ed25519 trust boundary.

### Added
- **Format** (`src/format.cyr`): 64-byte header (magic/version/count/offsets +
  `sig_off`/`sig_len`) + typed 144-byte manifest entries (name[48] / dtype /
  ndim / shape[8] / data_off / data_len) + 8-byte-aligned payload. All fields
  i64-aligned. `dtype` set: `f64`, `int8`, `ternary`, `nf4`.
- **Builder / reader**: `tula_builder_new` / `tula_builder_add` /
  `tula_serialize` / `tula_builder_finish` (unsigned); `tula_open` (magic +
  version validation) + accessors (`tula_count`, `tula_entry`,
  `tula_entry_{name,dtype,ndim,dim,data,data_len}`, `tula_find`,
  `tula_total_len`, `tula_is_signed`).
- **Signed header (M0b, `src/sign.cyr`)**: Ed25519 sign/verify over the file
  content `[0..sig_off)` (header incl. the sig fields ‖ manifest ‖ payload),
  signature appended at `sig_off`. `tula_builder_finish_signed(b, sk)` +
  `tula_verify(r, pk)` → `TULA_SIG_OK` / `TULA_SIG_BAD` / `TULA_SIG_UNSIGNED`.
  Crypto is **sigil** (Ed25519); keys are the caller's (tula owns no key mgmt).
- Error codes + name lookup (`src/error.cyr`).
- `programs/smoke.cyr` link-check; **30 assertions** across 2 suites —
  `tests/tcyr/roundtrip.tcyr` (22: bit-identical round-trip, bad-magic +
  short-buffer rejection, find, version) and `tests/tcyr/sign.tcyr` (8:
  sign→verify OK, tampered-payload → BAD, wrong-key → BAD, unsigned → UNSIGNED).
- **CI** (`.github/workflows/ci.yml`): build+test, lint, fmt-check, vet,
  dist-sync, ELF check, security scan, docs/version consistency.
- **Release** (`.github/workflows/release.yml`): on a `0.1.0` (or `v0.1.0`) tag —
  CI gate → build/test → regenerate `dist/tula.cyr` → archive (src tarball +
  `tula.cyr` + SHA256SUMS) → GitHub release (flagged pre-release for 0.x).

### Notes
- File I/O (mmap read / write-to-disk, round-trip a real attn11 checkpoint file)
  is the next bite (M1) — see `docs/development/roadmap.md`.
- Deps: stdlib + **sigil** (Ed25519). Local dev resolves sigil via
  `path = "../sigil"`; **CI/release resolve it via `[deps.sigil]` git+tag, so
  the sigil tag (3.9.9) must exist on GitHub** for CI + the 0.1.0 release.
- Cyrius pin **6.3.27**.
