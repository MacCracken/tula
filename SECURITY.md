# Security Policy

`tula` is the AGNOS sovereign weight-file **codec** — it serializes and parses a
typed tensor manifest + payload with a `sigil`-signable header. It loads
**foreign, untrusted checkpoints**, so its reader is a security boundary.

## Threat model

- **The reader is the trust boundary.** `tula_open` / `tula_validate` treat every
  input file as hostile: lying offsets, truncation, absurd counts/sizes, overflow
  attempts, and unterminated names are all rejected with a specific `TULA_ERR_*`
  code, never OOB-dereferenced or crashed on. This is fuzzed (>10⁶ iterations,
  `programs/fuzz.cyr`) and unit-covered (`tests/tcyr/hardening.tcyr`).
- **The signed header is the authenticity boundary — `sigil` owns the crypto.**
  tula validates *structure*; `sigil`'s Ed25519 validates *authenticity*. The
  signature covers the file content `[0, sig_off)` (header including the
  `sig_off`/`sig_len` fields, so they are tamper-evident, ‖ manifest ‖ payload).
- **Keys are the caller's.** tula owns no key management, generation, or storage.
  `tula_builder_finish_signed(b, sk)` and `tula_verify(r, pk)` take caller-held
  keys; protecting the secret key is the caller's responsibility.
- **The writer is trusted.** The builder/serializer is your own code producing a
  file; it trusts its inputs (e.g. it does not guard against a caller that
  accumulates > 2⁶³ bytes of tensors). Untrusted data enters only through the
  reader.
- **Out of scope** (by design — ADR 0001): the model/checkpoint *store*, the
  *importer*/LoRA path (`anukulana`), and tensor algebra (`rosnet`). tula does not
  interpret tensor semantics.

## Guarantees the reader provides

For any buffer where `tula_open(buf, len) != 0`:

- Every manifest entry lies within `[buf, buf+len)`; every tensor's
  `data_off + data_len ≤ payload_len` and stays within the buffer.
- Structural invariants hold: `manifest_off == 64`,
  `payload_off == 64 + count*ENTRY_SIZE ≤ len`, `payload_off + payload_len ≤ len`,
  `ndim ∈ [0, 8]`, NUL-terminated names, `sig_len ∈ {0, 64}` with
  `sig_off == content_len` and the 64-byte signature fully present.
- Resource caps bound the input: `≤ 2²⁰` tensors, `≤ 2⁴⁰` bytes total. The file
  readers apply the size ceiling *before* allocating/mmap'ing (no decompression-
  bomb-style over-allocation).
- All arithmetic on untrusted fields is overflow-safe.

## Caller responsibilities

- **Before unpacking a foreign quantized tensor**, call `tula_entry_payload_ok(e)`
  and proceed only if it returns 1. The dtype unpack helpers
  (`tula_ternary_unpack` / `tula_int8_dequant` / `tula_nf4_unpack`) are pure,
  caller-driven transforms sized by the element count *you* pass; a lying `shape`
  whose stored `data_len` is too small would otherwise drive an over-read.
  `tula_entry_payload_ok` cross-checks dtype+shape against `data_len`
  (overflow-safe) so this is a one-line guard.
- **Verify signatures you rely on.** `tula_verify` returns `TULA_SIG_UNSIGNED` /
  `TULA_SIG_OK` / `TULA_SIG_BAD` — treat `UNSIGNED` and `BAD` as untrusted.
- **Manage your own keys.** Use a trustworthy source for `sk`/`pk`.

## Reporting a vulnerability

Report suspected vulnerabilities privately to the maintainer
(<robert.maccracken@gmail.com>) rather than opening a public issue. Please
include a reproduction (a crafted file or a failing `tula_validate` case) and the
Cyrius toolchain version. A security audit lives in
[`docs/audit/`](docs/audit/2026-07-01-audit.md).
