# Stability Policy

`tula` follows [SemVer](https://semver.org/). This document states what the
version number promises once **v1.0** ships.

## The frozen surface

At v1.0 the public API in [`docs/api.md`](docs/api.md) is **frozen**:

- **On-disk format v1** — the 64-byte header and 144-byte manifest entry layout,
  field offsets, `TULA_MAGIC`, `TULA_VERSION`, the dtype codes
  (`TULA_DT_F64/INT8/TERNARY/NF4`, from 1.3.0 `F32/F16/BF16` with ADR 0005's
  conversion semantics, from 1.7.0 `I16/I32/I64/U8/BOOL` with ADR 0009's raw
  encodings and BOOL's 0/1 rule, and from 1.8.0 `F8_E4M3/F8_E5M2` with ADR
  0010's conversion semantics and `INT4` with ADR 0011's nibble order, its
  unused-nibble rule and the Q4_0 quantization rule), the signed-header scheme (Ed25519 over `[0, sig_off)`,
  `sig_len ∈ {0, 64}`), and from 1.3.0 the long-name convention (ADR 0004): the
  key formula, the `__tula.names__` table layout, and its magic. From 1.6.0 also
  the metadata convention (ADR 0008): the `__tula.meta__` table's position,
  layout and magic, the key rules and the reserved `tula.` prefix, the
  UTF-8-text values, and the caps (`TULA_META_*`). From 1.11.0 also the shard-set
  convention (ADR 0014): the `tula.shards` key, its line format and ordering,
  SHA-256 over each shard's first `size` bytes, file names in the manifest's
  directory, and a manifest holding no tensors. A file written
  by v1.x opens on any later 1.x, and vice versa. An older reader sees a
  long-named tensor by its key.
- **Public functions** — the builder, reader, accessors, signature, file-I/O, and
  dtype helpers documented in `docs/api.md`, with their signatures and semantics;
  from 1.9.0 also `tula_unpack_par` (ADR 0012), whose output is the serial
  helper's at any thread count, from 1.10.0 `tula_open_protected` (ADR 0013)
  with its guarantee: no later change to the file reaches the reader, and from
  1.11.0 the shard-set calls (`tula_builder_set_shards`, `tula_set_*`, ADR 0014).
- **Public constants** — `TULA_DT_*`, `TULA_SIG_*`, the `TULA_ERR_*` codes and
  their numeric values, and the format constants (`TULA_HEADER_SIZE`,
  `TULA_ENTRY_SIZE`, `TULA_NAME_CAP`, `TULA_MAXDIM`, `TULA_BUILDER_MAX`,
  `TULA_NF4_BLOCK`, from 1.8.0 `TULA_INT4_BLOCK`, from 1.11.0 the
  `TULA_SET_PROTECTED` flag, `TULA_READ_MAX_TENSORS`, `TULA_READ_MAX_BYTES`, and
  from 1.11.0 `TULA_SHARDS_MAX`, a cap that may be raised like them).

## What each bump means (post-1.0)

- **PATCH** (`1.0.x`) — bug fixes, doc/test/bench changes, internal refactors. No
  API or format change.
- **MINOR** (`1.x.0`) — **additive only**: new functions, new `TULA_DT_*` /
  `TULA_ERR_*` values, new optional helpers. Existing signatures, semantics,
  constant values, and the on-disk layout are unchanged. Old files still read;
  new files written without new features still read on older 1.x.
- **MAJOR** (`2.0.0`) — a breaking change: a format-layout change
  (`TULA_VERSION` bump), a removed/renamed public function, a changed signature or
  semantic, or a changed constant value. Comes with a migration note in the
  CHANGELOG and reader back-compat consideration for the old format version.

## Not covered by the freeze

These may change in a MINOR release without a major bump:

- **Internal helpers** not listed in `docs/api.md` — e.g. `tula_align8`,
  `tula_name_write`, `tula_serialize`, `tula_hdr_total`, `tula_nf4_nearest`, and
  every `_tula_*` function. Treat them as private, together with the builder's
  in-memory layout and the internal tuning constants (`TULA_BHDR_SIZE`,
  `TULA_BENTRY_SIZE`, `TULA_STRICT_SORT_MIN`, `TULA_STRICT_STACK_N`, from
  1.5.0 the index layout `TULA_IDX_HDR` / `TULA_IDX_REC`, from 1.11.0 an open
  set's layout (`TULA_SET_HDR`), and from 1.9.0 the
  parallel unpack's `TULA_PAR_MAX_THREADS` / `TULA_PAR_MIN_CHUNK`, which change
  how a call is split but never its output).
- **Benchmark numbers** and the fuzz/bench harness internals.
- **The exact `TULA_ERR_*` returned** for a given malformed input may be refined
  to a more specific code (the *set* of codes only grows; a given input keeps
  returning *some* non-`TULA_OK` code — rejection behavior is stable, the label
  may sharpen).
- **Resource-cap values** (`TULA_READ_MAX_*`) may be raised (never lowered) in a
  MINOR release to admit larger real-world files.

## Format-version changes are coordinated

A `TULA_VERSION` bump is a MAJOR event affecting every consumer
(`rupantara` / `anukulana` / the murti load-seam / the control-plane store). It
is planned and announced, never incidental — see ADR 0002 for why v1 was
preserved through the M2 dtype work.
