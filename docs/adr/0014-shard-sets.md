# 0014 — Sharded checkpoints: a signed manifest of shard digests, in the codec

**Status**: Accepted
**Date**: 2026-11-12

## Context

A 70B+ checkpoint ships as many files.
- **safetensors** writes `model-00001-of-00015.safetensors`… plus an unsigned
  `model.safetensors.index.json` that maps each tensor name to its file.
- **GGUF's split files** carry `split.no` / `split.count` keys in each part, and
  a loader finds the parts by their file-name pattern.

Neither binds the parts together.

tula doesn't need shards for size. One file holds up to `TULA_READ_MAX_BYTES`
(1 TiB), the streaming writer has no 2 GiB cap, and `make bigfile` reads a
2.36 GB file with a tensor over INT_MAX bytes. What a set of files would add:

- **Set integrity.** Each file signed on its own leaves the set unbound. A
  shard from an older release, a missing shard or a shard given twice each
  passes every per-file check.
- **Verification cost.** Ed25519 hashes the whole signed content with SHA-512,
  twice to sign and once to verify. sigil's SHA-512 runs at about 18 MB/s on
  the reference machine (sigil's open issue), so verifying a 140 GB checkpoint
  (70B in BF16) takes about 2.2 hours. Its SHA-256 runs at 320 MB/s on one
  thread with SHA-NI, and about 1.6 GB/s on 8 threads hashing separate files.
- **Name resolution** across files, and finding a tensor's sidecar in another
  file.

The roadmap left the question of whose job this is. It could be a codec
convention, or the control-plane store's (ADR 0001 gives the store indexing,
dedup and eviction, over vahana/sankoch).

## Decision

**A shard set is a manifest file plus shard files in the same directory, and
it is the codec's.** Binding a model's bytes and authenticating them is the
signed header's job, tula's trust boundary, and a loader reading from local
disk needs it without the store. No format change.

- **The manifest** is an ordinary v1 file with no tensors: only its metadata
  table (ADR 0008).
  - The reserved key `tula.shards` lists the shards, one line each:
    `<sha256> <size> <name>\n`.
  - `sha256` is 64 lowercase hex digits over the shard's first `size` bytes.
  - `size` is the shard's total length, in decimal, with no leading zeros.
  - `name` is the shard's file name in the manifest's directory: 1–255 bytes of
    printable ASCII (`0x21`–`0x7E`) or UTF-8 above it, with no `/` or `\`, and
    not `.` or `..`.
  - Lines are in strictly increasing byte order of name, so names are unique by
    construction and checked in one pass, even on crafted input.
  - 1 to `TULA_SHARDS_MAX` (4,096) shards. Each shard is one mapping, and Linux
    allows ~65,000 per process.
  - Other metadata (`hf.config`, provenance) sits beside the key: set-level
    metadata.
- **Signing.** The manifest is signed with Ed25519. Its signature covers every
  shard's digest, so shards need no signature of their own. They may carry one,
  and the set doesn't check it. Verifying a set is one signature over a small
  file, then a SHA-256 of each shard. The shards are independent, so they hash
  in parallel.
- **Shards** are ordinary, strict-valid tula files, and none is itself a
  manifest.
  - Tensor names are unique across the whole set, compared as one file's strict
    validator compares them: stored name fields, so long names by their keys.
  - A shard may have metadata of its own; the set doesn't merge it.
- **Strict validation.** A file whose metadata holds `tula.shards` is a
  manifest. Its value must be canonical as above, and the file must hold no
  entry but its metadata table. Otherwise `tula_validate_strict` returns
  `TULA_ERR_SHARDS` (20, new). The prefix `tula.` has been reserved since 1.6
  and refused by its writer, so no earlier writer made such a file. Older
  readers see an empty file whose metadata reads as usual.
- **Writing.** `tula_builder_set_shards(b, paths, n, nthreads)` opens each
  shard, strict-validates it and hashes it (in parallel), then sorts by name
  and sets `tula.shards`. A manifest builder refuses tensors, and a builder
  holding tensors refuses shards. The importer chooses the shard layout,
  usually its source's.
- **Reading.** `tula_set_open(path, pk, flags, nthreads, rc)` does these steps:
  - opens the manifest with `tula_open_protected` (it's small);
  - strict-validates it and, with `pk`, requires a valid signature;
  - parses the shard list;
  - maps each shard, or opens it protected with `TULA_SET_PROTECTED`;
  - checks every size and SHA-256 in parallel, strict-validates every shard,
    and refuses nesting and duplicate names;
  - sorts the set's names once.

  On failure `rc` gets the code and the shard it concerns. The calls
  `tula_set_find`, `tula_set_reader`, `tula_set_find_scale`, `tula_set_shards`,
  `tula_set_shard`, `tula_set_tensors`, `tula_set_manifest` and
  `tula_set_close` complete it.
- **What stays the store's:** where the files live, downloading, caching,
  dedup and versions. The manifest names files only within its own directory.

## Consequences

- **Positive**
  - **A set is bound.** A swapped, missing or repeated shard fails its digest
    or the shard list.
  - **Verification is 17× faster on one thread, and ~90× on 8**, at today's
    sigil speeds: about 90 s for 140 GB instead of 2.2 hours. It needs no sigil
    change and no new signature scheme. A big single file gains the same path
    as a one-shard set.
  - **A loader can check only the shards it reads**, from their own digests.
    For example, a pipeline-parallel rank reads only its layers.
  - **Old readers still work.** Every shard is an ordinary file, and a manifest
    is one that 1.6+ readers open.
- **Negative**
  - **SHA-256's collision resistance** now binds the shards to the signature.
    That is standard for signed digest lists, and the signature itself is
    unchanged.
  - **A mapped set is trusted only while its files aren't rewritten**, as with
    `tula_open_mmap`. `TULA_SET_PROTECTED` copies instead, unless a shard is
    fs-verity.
  - **A set is two kinds of file to keep together,** in one directory.
  - **SHA-256 without SHA-NI is slower.** sigil's software path on CPUs without
    it wasn't measured here.
- **Neutral**
  - **Splitting one builder into shards automatically**
    (`tula_builder_write_sharded`) is left for later. Importers mirror their
    source's layout and write each shard with the existing writers.
  - **Partial verification** (opening only some shards) is possible from the
    digests, but `tula_set_open` checks the whole set. A partial open is a later
    MINOR if a consumer needs one.

## Alternatives considered

- **The store's job:** rejected. The binding is integrity, which is the
  codec's trust boundary. A loader on local disk would need the store just to
  know a set is whole.
- **Membership keys in each shard** (`tula.shard.set`, `.index`, `.count`, each
  shard signed): rejected. Every shard still costs a SHA-512 signature check.
  The set is bound only as long as the writer never reuses a set id.
- **A JSON index beside the shards** (safetensors'): rejected. It is unsigned,
  and it would add a second parser. The manifest is a tula file, signed with
  the existing code.
- **A reserved binary tensor for the digest table:** rejected. Metadata text is
  enough: a 16 MiB value holds ~150,000 lines. It is readable through
  `tula_meta_get` by every 1.6+ reader, and needs no new position rule.
- **The manifest inside shard 0:** rejected. Shard 0 would have to be written
  last, after hashing the others, and it couldn't then be an ordinary shard.
- **SHA-512 digests:** rejected. They are no faster than the per-file
  signatures this avoids. sigil has no faster hash than SHA-256.
