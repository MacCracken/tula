# 0004 — Long tensor names live in a names-table tensor; the entry holds a key

**Status**: Accepted
**Date**: 2026-11-04

## Context

The v1 manifest entry gives a tensor name 48 bytes: at most 47 characters plus
the NUL. That field is frozen with format v1 (ADR 0003). Real checkpoint names
don't fit:

- Mixtral: `model.layers.0.block_sparse_moe.experts.0.w1.weight` — 51 characters.
- PEFT/LoRA adapters: `base_model.model.model.layers.0.self_attn.q_proj.lora_A.weight`
  — 62 characters. Its `lora_B` twin truncates to the **same** 47 bytes, so a
  truncating writer stores two tensors under one name, and `tula_find` returns
  the first for both. For anukulana (the LoRA importer) that is a wrong-tensor
  bug, not a cosmetic one.

1.0–1.1's plain add truncates silently. 1.2.0's `tula_builder_add_checked`
refuses names over 47 characters, which makes the collision impossible but
leaves these models unwritable. A format v2 with variable-length names would
break every 1.x reader (a MAJOR, STABILITY.md). ADR 0002 already answered a
similar "the entry has no room" question with a sidecar tensor and no format
bump.

## Decision

**Full names over 47 bytes are stored in one reserved tensor; the entry's
48-byte field holds a deterministic key derived from the full name.** No format
change: `TULA_VERSION` stays 1, the entry stays 144 bytes.

- **The key** for a full name `N` (more than 47 bytes) is 47 bytes:
  `N[0..30)` ‖ `~` ‖ 16 lowercase hex digits of FNV-1a-64(`N`). FNV-1a-64 is
  offset basis `0xcbf29ce484222325`, prime `0x100000001b3`, over `N`'s bytes
  (no NUL). The 30-byte prefix keeps keys readable in old tools. The key is a
  function of the name alone, so it never depends on the rest of the file.
- **The names table** is a tensor named `__tula.names__`, the **last** manifest
  entry, dtype `TULA_DT_INT8`, `ndim` 1, shape `[data_len]`. Its payload is:
  - `+0` the magic `"tula.nm1"` (8 bytes);
  - `+8` `L`, the record count (at least 1);
  - `+16` `L` records of 24 bytes: `entry_index`, `name_off`, `name_len` (i64
    LE). They are sorted by `entry_index`, strictly increasing, and every index
    is before the table's own. `name_off` is relative to the table payload.
  - then the names, each followed by a NUL, packed in record order.

  Only names over 47 bytes have a record. A name of 47 bytes or fewer stays in
  its entry, as in 1.0.
- **Recognition.** The last entry is the names table only if it is named
  `__tula.names__`, is int8 with `ndim` 1 and `data_len ≥ 16`, and its payload
  starts with the magic. Any other tensor with that name is an ordinary tensor.
  That keeps every 1.2 file meaning what it meant.
- **Lookups verify.** `tula_find_name(r, name)` derives the key, finds the
  entry, then compares the table's full name with `name`. It never returns a
  tensor whose full name differs, even on a hash collision.
  `tula_entry_full_name(r, e)` returns the table's name for a long-named entry
  and the in-place name otherwise. Malformed records fall back to the in-place
  key, and every read is bounds-checked.
- **Writing** goes through `tula_builder_add_long`, which is
  `tula_builder_add_checked` except that a name over 47 bytes is stored this way
  instead of refused. Duplicates are checked on the stored field (the key), so
  two equal long names are refused, and so (with probability ~2⁻⁶⁴ per pair) are
  two different long names whose prefix and hash both match. That is loud, never
  silent. The reserved name itself is refused, by `add_long` always and by
  `add_checked` once the builder holds a long name.
- **Strict.** `tula_validate_strict` requires a recognized table to be
  canonical: exactly the packing above, every `name_len > 47`, no NUL inside a
  name, each referenced entry's field equal to the key of its name. Anything
  else is `TULA_ERR_NAMES`.

## Consequences

- **Positive** — real HF/LoRA names round-trip exactly, and the LoRA
  `lora_A`/`lora_B` collision is the acceptance test. There's no format bump.
  **Every 1.x reader still opens these files**: 1.0–1.2 see the keys as names
  and the table as one more int8 tensor. 1.2's strict validator accepts them too
  (the table is a canonical int8 tensor, and the keys are distinct names).
  Full-name lookup is a hash plus a binary search.
- **Negative** — an old reader sees `…~1a2b3c4d5e6f7a8b` instead of the real
  name, and must upgrade to resolve it. `__tula.names__` is now a reserved name
  for writers using long names. The FNV-1a key and the table layout are now
  part of the v1 format's conventions, frozen as the names themselves are.
- **Neutral** — `tula_find_scale` resolves `"<full name>.scale"` through the table,
  so long-named quantized tensors keep ADR 0002's sidecar convention.

## Alternatives considered

- **Format v2 with variable-length names** — rejected for now: a MAJOR that every
  consumer must take at once, for something a reserved tensor carries within v1.
  It stays the fallback (the roadmap's v2 potential items) if this proves
  insufficient.
- **Field = the truncated name, table maps entry → full name** — rejected: the
  truncated prefix is exactly what collides, so lookup by full name would have to
  scan every candidate's full name, and old readers would still see two tensors
  with one name.
- **Field = an index-based key (`~0`, `~1`, …)** — rejected: the key would depend
  on position, not the name, so lookup by name means scanning the whole table,
  and appending or reordering tensors changes every key.
- **A cryptographic hash (e.g. SHA-256 from sigil)** — unnecessary: the key only
  has to be deterministic, and lookups verify the full name, so collisions can't
  return a wrong tensor. FNV-1a keeps the codec free of a crypto dependency on
  the read path. The writer refuses an (astronomically unlikely) collision
  instead of storing it.
- **Names in a side file** — rejected: a weight file must be self-contained.
