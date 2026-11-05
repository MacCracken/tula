# 0008 — File metadata lives in a sorted key/value table tensor

**Status**: Accepted
**Date**: 2026-11-04

## Context

A tula file holds tensors and nothing else. Real checkpoints also carry facts
about themselves: the architecture and its config, the tokenizer they pair with,
a licence, and the importer's record of what it converted (source file, its
digest, the converter's version). safetensors has a `__metadata__` string map,
and GGUF has a typed key-value section. Without one, an importer has to ship a
side file (unsigned, separable from the weights) or smuggle text into an int8
tensor by an unwritten convention.

The v1 layout is frozen (ADR 0003). ADR 0004 already added a reserved trailing
tensor (`__tula.names__`) that every older 1.x reader opens as an ordinary int8
tensor. 1.3–1.5 readers find it as the **last** entry, so nothing may be
appended after it.

## Decision

**Metadata is a reserved int8 tensor `__tula.meta__` holding sorted, unique
key/value text pairs. It sits after every ordinary tensor and before the names
table, and is signed with the rest of the file.** No format change.

- **Position.** The table is the last entry, or the second-to-last when the last
  is a recognized names table. The names table stays last, so 1.3–1.5 readers
  still find it.
- **Recognition**, as ADR 0004: named `__tula.meta__`, int8, `ndim` 1, at least
  16 bytes, its payload starting with the magic `"tula.mt1"`, a pair count that
  fits its bytes, and in the position above. Any other tensor of that name is
  ordinary, so every 1.2–1.5 file means what it meant.
- **Payload**:
  - `+0` the magic;
  - `+8` `P`, the pair count (at least 1);
  - `+16` `P` records of 32 bytes: `key_off`, `key_len`, `val_off`, `val_len`
    (i64 LE, offsets relative to the payload), **sorted by key bytes, keys
    unique**;
  - then, for each record in order, the key, a NUL, the value, a NUL — packed.
- **Keys** are 1–255 bytes of ASCII letters, digits, `.`, `_` or `-`, starting
  with a letter. The recommended form is `<namespace>.<name>` (`hf.config`,
  `anukulana.source.sha256`). Keys starting `tula.` are **reserved** for keys
  tula itself may define later, and the 1.6 writer refuses them. The validator
  does not, so a later writer's `tula.*` keys still read.
- **Values** are text: well-formed UTF-8 (no overlongs, surrogates or code points
  past U+10FFFF), no NUL, at most 16 MiB each. They are NUL-terminated in the
  file, so `tula_meta_get` returns a zero-copy C string. Binary data belongs in a
  tensor.
- **Caps**: at most 4,096 pairs and 64 MiB of table, enforced by the writer and
  by the strict validator. Real metadata runs to tens of keys (GGUF files carry
  ~30–50). The builder keeps its pairs sorted as they are set, which stays fast
  at that cap.
- **Writing**:
  - `tula_builder_set_meta(b, key, value)` sets or replaces a key. The builder
    copies both strings and writes the table in key order at `finish` or in the
    streaming writers, so the same pairs always give the same bytes, whatever
    order they were set in.
  - tula writes no keys of its own (no timestamps, no writer version), so output
    stays a pure function of the inputs.
  - `__tula.meta__` is refused as a tensor name by `add_long`, and by
    `add_checked` once metadata is set.
- **Reading**:
  - `tula_meta_count(r)`;
  - `tula_meta_get(r, key)`, a binary search, O(log P);
  - `tula_meta_key(r, i)` / `tula_meta_value(r, i)`, the pairs in key order.

  Each record is bounds-checked when read; one that doesn't hold up reads as
  absent.
- **Strict.** `tula_validate_strict` requires a recognized table to be canonical:
  exact packing, keys sorted and unique, the key charset, valid UTF-8 values
  within the caps. Anything else is `TULA_ERR_META` (18), which the writer also
  returns for a bad key or value.

## Consequences

- **Positive**:
  - A checkpoint carries its own description and provenance, and the Ed25519
    signature covers it, so tampering with metadata is as detectable as with
    weights.
  - Every 1.x reader opens these files. 1.2–1.5's strict validator accepts them:
    a canonical int8 tensor with a unique name.
  - Lookup is a binary search; iteration is in a defined order.
- **Negative**:
  - Values are text only, with no typed values like GGUF's. Numbers and lists
    are written as text (JSON, typically).
  - Two names are now reserved: `__tula.meta__`, and the `tula.` key prefix.
  - The 16 MiB value cap means a giant config must be split or go in a tensor.
- **Neutral**: an importer decides its key namespace. anukulana would naturally
  use `anukulana.*` for provenance and `hf.*` for copied Hugging Face config.

## Alternatives considered

- **Typed values (GGUF-style ints, floats, arrays)** — rejected for v1: the
  writer, reader and validator would each grow a type system for a need that
  text (JSON) already meets. It can come back as a v2 header section if it earns
  its place.
- **Metadata after the names table** — rejected: 1.3–1.5 readers look for the
  names table as the last entry. Putting the metadata last would make those
  readers miss every long name.
- **Folding metadata into the names table** — rejected: it would mix two
  conventions in one layout, and `__tula.names__` must stay exactly what ADR
  0004 froze.
- **Unsorted pairs, last-wins on duplicates** — rejected: ambiguous (a reader
  that scans and one that searches could disagree), and not canonical. Sorted
  unique keys give one answer and one byte layout.
- **A side file** — rejected: unsigned and separable from the weights it
  describes.
