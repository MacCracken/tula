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
- **The writer is trusted, but fails loud.** The builder/serializer is your own
  code producing a file, and it trusts the pointers you give it. Since 1.1.2
  `tula_builder_add` refuses arguments that would corrupt the buffer or produce a
  file tula's reader rejects (`ndim` outside 0..8, a negative `data_len`, a
  payload over `TULA_READ_MAX_BYTES`), and `tula_builder_finish` returns 0 when
  the allocation fails. Untrusted data enters only through the reader.
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
- Resource caps bound the input: `≤ 2²⁰` tensors, `≤ 2⁴⁰` bytes total.
- **The file readers check the header against the file** (1.1.2). Before
  allocating or mapping, `tula_read_file` and `tula_open_mmap` require the file
  to hold at least the total its header declares. A truncated file is rejected
  instead of being mapped past its end (where a read raised SIGBUS), and a tiny
  file cannot make the heap reader reserve what its header claims. A file that
  `tula_open_mmap` maps and then rejects is unmapped again.
- All arithmetic on untrusted fields is overflow-safe. The manifest is
  fixed-width (48-byte names, 144-byte entries, a capped count), so there are no
  attacker-sized strings or arrays to overflow — the class behind the 2024 GGUF
  parser CVEs (see the [audit](docs/audit/2026-11-04-audit.md)).

## What the reader does NOT reject

`tula_validate` checks **bounds**, not **consistency**. A file that passes it
can still have tensors that overlap or leave gaps, duplicate names, a `data_off`
that is not 8-byte aligned, a shape that does not match `data_len`, or an
unknown dtype. None of these lets tula's accessors read out of bounds, but a
consumer that cares must check them itself (a strict validator is planned for
1.2.0). Overlap matters for cost: many entries pointing at the same bytes make
a small file decode into a lot of work.

## Caller responsibilities

- **Before unpacking a foreign quantized tensor**, call `tula_entry_payload_ok(e)`
  and proceed only if it returns 1. The dtype unpack helpers
  (`tula_ternary_unpack` / `tula_int8_dequant` / `tula_nf4_unpack`) are pure,
  caller-driven transforms sized by the element count *you* pass; a lying `shape`
  whose stored `data_len` is too small would otherwise drive an over-read.
  `tula_entry_payload_ok` cross-checks dtype+shape against `data_len`
  (overflow-safe) so this is a one-line guard.
- **Check a quantized tensor's scale sidecar too.** `tula_nf4_unpack` reads
  `tula_nf4_blocks(n, block)` scales from the `"<name>.scale"` tensor. Run
  `tula_entry_payload_ok` on the sidecar as well, and check that its element
  count is at least that many. A 0-dim entry has no element count, so check its
  `data_len` yourself if you read it as a scalar.
- **Verify signatures you rely on.** `tula_verify` returns `TULA_SIG_UNSIGNED` /
  `TULA_SIG_OK` / `TULA_SIG_BAD` — treat `UNSIGNED` and `BAD` as untrusted.
  Stripping the signature from a signed file gives a valid *unsigned* file, so a
  consumer that requires signatures must reject `UNSIGNED`, not only `BAD`.
- **Map only files nobody else writes.** A `tula_open_mmap` mapping shows the
  file as it is now: a process that truncates or rewrites it after validation
  can change validated bytes, or make a later read SIGBUS. Use `tula_read_file`
  (a private copy) for files in a location others can write.
- **Keep names unique and under 48 bytes when writing.** Names over 47
  characters are truncated (frozen v1 behaviour), so two distinct long names can
  become the same stored name. The LoRA pair `…q_proj.lora_A.weight` /
  `…q_proj.lora_B.weight` under a `base_model.model.model.layers.N.self_attn.`
  prefix does. `tula_find` returns the first match.
- **Manage your own keys.** Use a trustworthy source for `sk`/`pk`.

## Reporting a vulnerability

Report suspected vulnerabilities privately to the maintainer
(<robert.maccracken@gmail.com>) rather than opening a public issue. Please
include a reproduction (a crafted file or a failing `tula_validate` case) and the
Cyrius toolchain version. Audits live in [`docs/audit/`](docs/audit/): the
latest is [2026-11-04](docs/audit/2026-11-04-audit.md) (P(-1), 1.1.2); the
first is [2026-07-01](docs/audit/2026-07-01-audit.md).
