# 0001 — tula scope: the weight-file codec, nothing more

**Status**: Accepted
**Date**: 2026-07-01

## Context

The AGNOS Type-3 ("Pre-Trained") path needs to run and adapt someone else's
pretrained checkpoint sovereignly. Three concerns are adjacent but distinct: a
weight-file **format** (bytes ↔ tensors), a **store** (indexed, dedup,
eviction), and the **importer/adapter** (foreign checkpoint → layout → run →
LoRA/QLoRA). Collapsing them repeats the Rust-era `murti` mistake (a broker that
owned everything). See the AGNOS planning doc `type3-weight-import.md`.

## Decision

`tula` is **only the codec**: serialize/parse a typed tensor manifest + payload
with a sigil-signable header. In scope:

- The on-disk format (header + manifest + payload; dtype set f64 / int8 /
  ternary / nf4; i64-aligned, mmap-friendly).
- Builder (serialize) + reader (validate + accessors).
- The sigil-signed header as the trust boundary (`sig_off`/`sig_len` reserved
  in M0; wired M0b).
- File I/O (mmap read / write-to-disk) — M1.

Out of scope (and their homes):
- **Model/checkpoint store** → the control-plane (over vahana/sankoch + sigil).
- **Importer + run + LoRA/QLoRA** → `anukulana` (the Type-3 reference).
- **Transformer forward** → `rupantara` (extracted from attn11) + `rosnet`.
- **Tensor algebra** → `rosnet`.

## Consequences

- **Positive**: a small, stable, widely-consumed codec (attn11 checkpoints,
  tentib ternary weights, the murti load-seam, the control-plane store all use
  it) with a clean single responsibility; coupling at the ABI (`dist/tula.cyr`),
  not the codebase.
- **Negative**: consumers must own their own store/import logic; tula does not
  hide those.
- **Neutral**: the multi-consumer reality means tula is a lib from the start
  (the second-consumer trigger is effectively immediate).

## Alternatives considered

- **Fold the store into the format** — rejected: a stateful store and a
  stateless codec have different lifecycles (the same category error `murti`
  made). The store is the control-plane's.
- **Put the format inside `anukulana`** — rejected: the format has many
  consumers beyond the importer; keeping it separate avoids re-implementation.
