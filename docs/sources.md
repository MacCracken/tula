# Sources

> **Last Updated**: 2026-07-01

tula's dtype payload helpers implement published quantization schemes. Every
magic constant and formula traces to a source here. tula is the *codec* — it
stores/reconstructs these representations; it does not invent the schemes.

## NF4 — 4-bit NormalFloat

**Used by**: `tula_nf4_level` / `tula_nf4_pack` / `tula_nf4_unpack`
(`src/dtype.cyr`). The 16 codebook constants are the NormalFloat4 quantiles.

- **Dettmers, T., Pagnoni, A., Holtzman, A., Zettlemoyer, L. (2023). "QLoRA:
  Efficient Finetuning of Quantized LLMs."** arXiv:2305.14314.
  <https://arxiv.org/abs/2305.14314> — defines NF4 (information-theoretically
  optimal 4-bit quantization for normally-distributed weights), blockwise absmax
  scaling, and double-quantization.
- **Reference implementation**: `bitsandbytes`
  (<https://github.com/bitsandbytes-foundation/bitsandbytes>) — the de-facto NF4
  codebook values tula mirrors (as f64 IEEE-754 bit patterns in `tula_nf4_level`)
  for interop with QLoRA-style consumers (`anukulana`).

The per-block **absmax** scale rides in a `"<name>.scale"` sidecar tensor rather
than the codebook — see [ADR 0002](adr/0002-quant-scales-as-sidecar-tensors.md).
"Double-quant" is expressed by int8-quantizing that sidecar.

## Ternary {−1, 0, +1} — BitNet b1.58

**Used by**: `tula_ternary_pack` / `tula_ternary_unpack` / `tula_ternary_get`
(`src/dtype.cyr`). 2-bit codes (0→0, +1→1, −1→2), 4 per byte.

- **Ma, S., Wang, H., Ma, L., et al. (2024). "The Era of 1-bit LLMs: All Large
  Language Models are in 1.58 Bits."** arXiv:2402.17764.
  <https://arxiv.org/abs/2402.17764> — the ternary {−1,0,+1} weight scheme
  (log₂3 ≈ 1.58 bits) and the per-tensor absmean scale `γ`.
- **Ecosystem mirror**: tula's packing matches `tentib`'s `tpack2`/`tunpack2`
  (the AGNOS b1.58 reference), so ternary weights round-trip between them. The
  absmean `γ` is stored as a `"<name>.scale"` sidecar.

## int8 — absmax quantization

**Used by**: `tula_int8_quant` / `tula_int8_dequant` (`src/dtype.cyr`).
`scale = absmax / 127`; `q = clamp(round(x / scale), −127, +127)`.

- **Dettmers, T., Lewis, M., Belkada, Y., Zettlemoyer, L. (2022). "LLM.int8():
  8-bit Matrix Multiplication for Transformers at Scale."** arXiv:2208.07339.
  <https://arxiv.org/abs/2208.07339> — the standard per-tensor absmax int8
  quantization tula implements (the vanilla path; tula does not implement the
  paper's outlier decomposition — that is a consumer/tensor-lib concern).

## Ed25519 signed header

**Used by**: `tula_builder_finish_signed` / `tula_verify` (`src/sign.cyr`), over
`sigil`'s `ed25519_*`.

- **RFC 8032 — "Edwards-Curve Digital Signature Algorithm (EdDSA)."**
  <https://www.rfc-editor.org/rfc/rfc8032> — the signature scheme. tula owns only
  the layout (64-byte signature over content `[0, sig_off)`); the cryptographic
  implementation, including the §8.4 canonical-`S` malleability check, is
  `sigil`'s. See [`SECURITY.md`](../SECURITY.md) and the
  [audit](audit/2026-07-01-audit.md) §4.

## The bar

A reviewer unfamiliar with the domain should be able to trace any constant or
formula in `src/dtype.cyr` back to the source above and verify the implementation
against it.
