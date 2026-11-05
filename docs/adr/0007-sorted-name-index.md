# 0007 — The name index is a sorted array, not a hash table

**Status**: Accepted
**Date**: 2026-11-04

## Context

`tula_find` and `tula_find_name` scan the manifest: O(n) per lookup, ~3 ns per
entry. An importer that looks up every tensor of a checkpoint by name does
O(n²) work: 995 tensors for Mixtral-8x7B is about a million name comparisons, and
the format allows 2²⁰ tensors. The roadmap called for an index built once per
opened file.

The index is built over an **untrusted** file. A hash table keyed on its names is
open to hash flooding: names crafted to collide turn every lookup into a scan,
so the index is no better than no index, and building it is quadratic. A keyed
(random-seed) hash fixes that only while the seed stays secret. It also makes
lookup cost depend on a random draw, and adds a dependency on randomness at read
time. The strict validator (1.2.0) already met the same problem for its duplicate
check and sorted instead of hashing.

## Decision

**`tula_index_new(r)` builds a sorted array of (name hash, canonical name)
records; `tula_index_find(ix, name)` binary-searches it.** Every lookup is
O(log n) whatever the names; building is one heapsort, O(n log n) worst case.

- **Keys are canonical.** Each entry's stored name (up to its NUL; a long name's
  key, ADR 0004) is copied zero-padded into a 48-byte key, so bytes after a
  name's NUL never matter, exactly as `tula_find` ignores them.
- **Order is total**: by an unkeyed 64-bit hash of the key, then by the key's
  bytes, then by entry index. The hash only makes most comparisons one word, and
  colliding names cost a full 48-byte compare per step, never more steps. The
  index tiebreak makes the first match the lowest entry, as `tula_find` returns.
- **Same answers as `tula_find_name`, for every buffer.** A name of 47 bytes or
  fewer matches in place (never a long-named entry's key). A longer name is
  found through its key and accepted only if the names table holds that full
  name. `tula_index_find_scale(ix, e, need)` is `tula_find_scale` through the
  index. The test suite and the fuzzer check the equivalence on every accepted
  buffer.
- **One private mapping**: 32 + 64 bytes per tensor (a 16-byte record + a 48-byte
  key), released by `tula_index_free(ix)`. The index points into `r`, so it is
  valid while `r` is (until `tula_close_mmap(r)`, say).
- **The sort is the strict validator's** heapsort over 16-byte (hash, pointer)
  records, given a tiebreak flag. There is one sort implementation in tula.

## Consequences

- **Positive** — looking up every tensor of a checkpoint is O(n log n) instead
  of O(n²), with a worst case no crafted file can push past that. No randomness,
  no seed, and the same lookup cost on every run.
- **Negative** — a hash table would answer in O(1) expected time, while this is
  log₂ n comparisons (10 for 1,000 tensors). Each index costs 64 bytes per tensor
  until freed.
- **Neutral** — `tula_find` / `tula_find_name` stay as they are (stateless,
  O(n)) for the occasional lookup.

## Alternatives considered

- **Open-addressing hash table, unkeyed** — rejected: crafted collisions make it
  quadratic (the same reason the strict validator sorts).
- **Keyed hash (seed from `getrandom`)** — rejected: the worst case is only
  improbable, not impossible, and the read path would depend on randomness.
  Expected O(1) vs O(log n) is not worth either, at checkpoint sizes.
- **Sort the manifest in the file** (a canonical sorted order in format v1) —
  rejected: that is a format convention every writer must follow and every 1.x
  file already breaks. The index is a reader-side structure.
