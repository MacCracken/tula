# 0002 — Quantization scales are sidecar tensors, not an entry field

**Status**: Accepted
**Date**: 2026-07-01

## Context

M2 adds payload helpers for the quantized dtypes (`ternary`, `int8`, `nf4`).
Every one of them needs a **scale** to reconstruct real values from packed
codes:

- **ternary** (tentib b1.58): one per-tensor scalar `γ = absmean(w)`.
- **int8** (absmax): one per-tensor scalar `scale = absmax / 127` (or a per-row
  vector).
- **nf4** (QLoRA NormalFloat): one **per-block absmax** — an *array* of scales,
  one per block (block size 64 typical), plus optional double-quant.

The 144-byte manifest entry (`name[48] · dtype · ndim · shape[8] · data_off ·
data_len`) has no slot for a scale. The roadmap posed the choice: **(a)** extend
the entry with an `aux`/`scale` field (a `TULA_VERSION` + `TULA_ENTRY_SIZE`
bump), or **(b)** store scales as sidecar tensors. It tentatively preferred (a)
*"if the extra field stays small and general."*

## Decision

**Scales are stored as sidecar tensors by a documented naming convention — no
format change.** For a quantized tensor named `w`, its scales live in a second
tensor named `w.scale`:

- ternary `w` (dtype `TERNARY`) → `w.scale` is `f64[1]` (γ).
- int8 `w` (dtype `INT8`) → `w.scale` is `f64[1]` (or `f64[rows]` per-row).
- nf4 `w` (dtype `NF4`) → `w.scale` is `f64[n_blocks]` (per-block absmax).
- **double-quant** falls out for free: the `w.scale` tensor is itself just a
  tensor, so a consumer that wants to compress it stores it as `INT8` with its
  own `w.scale.scale` `f64[1]` — the same convention, one level down.

The M2 helpers (`src/dtype.cyr`) are **pure byte transforms** — they pack/unpack
codes and compute/consume a scale passed explicitly as a parameter. They never
read or write the file layout. `TULA_VERSION` stays `1`; `TULA_ENTRY_SIZE` stays
`144`. The `w` ↔ `w.scale` relationship is a **consumer convention** (owned by
the importer, e.g. anukūlana); the codec is oblivious — it just stores tensors.

## Consequences

- **Positive** — the on-disk format does not change, so the imminent v1.0 freeze
  and every existing consumer of the v1 layout are unaffected; scales are
  first-class, introspectable `f64` tensors whose **shape expresses the scale
  granularity** (scalar / per-row / per-block) that a single entry field never
  could; the helpers stay pure transforms, keeping tula a codec and not a tensor
  library (ADR 0001); double-quant composes with zero new machinery.
- **Negative** — a quantized tensor now costs two manifest entries, so it presses
  harder on `TULA_BUILDER_MAX` (a builder cap, cheaply raised — not a format
  constraint); the semantic tie between `w` and `w.scale` is a convention the
  consumer must honor, not something the codec enforces.
- **Neutral** — the `.scale` suffix is documented here and in `src/dtype.cyr`;
  tooling that wants to hide the pairing can wrap the builder in the consumer.

## Alternatives considered

- **(a) an `aux`/`scale` field in the entry** — rejected. It fails the roadmap's
  own *"small and general"* test: NF4's per-block scales are an *array*, not a
  scalar, so a single field cannot hold them — the array would have to live in
  the payload or a sidecar anyway, leaving the field used inconsistently (ternary
  and int8 only). And it forces a breaking `TULA_VERSION`/`TULA_ENTRY_SIZE` bump
  — all offset math and the reader — right before the v1.0 freeze, for no gain
  over the sidecar.
- **(c) embed scales inside the packed payload blob** (a self-describing blob per
  quantized tensor) — rejected as the *default*. It keeps one entry per tensor,
  but buries the scales in opaque bytes (not introspectable with the normal
  accessors), and makes tula own a container-within-a-container layout — codec
  scope creep. A consumer that wants a single self-contained blob can still build
  one on top of the pure helpers; the codec does not mandate it.
