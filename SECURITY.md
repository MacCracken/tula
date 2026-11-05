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
- **Writes don't destroy the previous file** (1.4.0, ADR 0006).
  `tula_builder_write_file(_signed)` and `tula_write_file_atomic` write a sibling
  temp file and rename it over the target only after an fsync. A failure or crash
  leaves the old file intact. The temp is created with `O_CREAT|O_EXCL` (a
  planted file or symlink at its name is never opened or followed; a new random
  name is tried) under a 64-bit random name, with the existing target's mode, so
  it is never more readable than the result. A symlink at the target is
  replaced, not written through. `tula_write_file` keeps its frozen
  truncate-and-write behaviour.
- **The signed streaming writer signs what it wrote.** It maps the temp file's
  content and signs the mapping. A process with write access to that temp file
  (only its owner, given its mode) could change it between the write and the
  signature. Write into directories only you control.
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

## Bounds vs consistency: `tula_validate` and `tula_validate_strict`

`tula_validate` (and so `tula_open` and the file readers) checks **bounds**, not
**consistency**. A file that passes it can still have tensors that overlap or
leave gaps, duplicate names, a `data_off` that is not 8-byte aligned, a shape
that does not match `data_len`, or an unknown dtype. None of these lets tula's
accessors read out of bounds. They stay accepted because 1.x writers can produce
some of them (the plain builder allows duplicate names).

**`tula_validate_strict` (1.2.0) rejects all of them.** It accepts only a
canonical buffer, exactly what a correct tula writer produces. Run it on any
file you didn't write. Overlap matters for cost too: many entries pointing at the
same bytes make a small file decode into a lot of work, and strict rejects that.
Its duplicate check sorts names (worst case O(n log n)) rather than hashing them,
so crafted names can't make it quadratic.

**The name index (1.5.0) is built over untrusted names**, so it is a sorted array
searched by bisection, never a hash table (ADR 0007). Crafted colliding names
cost a full name comparison per step, never more steps. Building is
O(n log n) and lookup O(log n) whatever the file holds. The fuzzer builds an
index for every accepted buffer, under the guard page, and checks that it agrees
with `tula_find_name`.

**Metadata (1.6.0) is read as untrusted too** (ADR 0008):
- The table is recognized only by its position, name, dtype, magic and a pair
  count that fits its bytes.
- Each record is bounds-checked when read; one that doesn't hold up reads as
  absent. Values are returned as NUL-terminated pointers into the file.
- `tula_validate_strict` additionally requires well-formed UTF-8 (no overlongs,
  surrogates or code points past U+10FFFF) and no NUL. A consumer that parses a
  value (as JSON, say) should strict-validate first, and still treat the text
  as input from whoever made the file.
- The signature covers metadata, so editing a value breaks it.
- The guard-page fuzzer mutates the table directly (phase G).

**The names table (1.3.0) is read as untrusted too.** It is recognized only by
its name, dtype, magic and a record count that fits its bytes. Each record is
bounds-checked when `tula_entry_full_name` reads it; one that doesn't hold up is
treated as absent, and the in-place key comes back. Nothing reads outside the
buffer, and the guard-page fuzzer (`make fuzz`, phase F) mutates the table
directly. `tula_validate_strict` also requires the table to be canonical, with
every key matching its name.

## Caller responsibilities

- **Before unpacking a foreign quantized tensor**, call `tula_entry_payload_ok(e)`
  and proceed only if it returns 1. The dtype unpack helpers
  (`tula_ternary_unpack` / `tula_int8_dequant` / `tula_nf4_unpack`) are pure,
  caller-driven transforms sized by the element count *you* pass; a lying `shape`
  whose stored `data_len` is too small would otherwise drive an over-read.
  `tula_entry_payload_ok` cross-checks dtype+shape against `data_len`
  (overflow-safe) so this is a one-line guard.
- **Check a quantized tensor's scale sidecar too.** `tula_nf4_unpack` reads
  `tula_nf4_blocks(n, block)` scales from the `"<name>.scale"` tensor. Get the
  sidecar with `tula_find_scale(r, e, need)` (1.2.0): it returns 0 unless the
  sidecar exists, is f64, and holds at least `need` scales. (By hand: run
  `tula_entry_payload_ok` on the sidecar and check its element count.)
  `tula_entry_payload_ok` treats a 0-dim entry as having no contract; under
  `tula_validate_strict` a 0-dim entry must hold exactly one element.
- **Verify signatures you rely on.** Stripping the signature from a signed file
  gives a valid *unsigned* file, so a consumer that requires signatures must
  reject `UNSIGNED`, not only `BAD`. `tula_verify_required(r, pk)` (1.2.0)
  returns `TULA_OK` only for a valid signature. With `tula_verify`, treat both
  `TULA_SIG_UNSIGNED` and `TULA_SIG_BAD` as untrusted.
- **Map only files nobody else writes.** A `tula_open_mmap` mapping shows the
  file as it is now: a process that truncates or rewrites it after validation
  can change validated bytes, or make a later read SIGBUS. Use `tula_read_file`
  (a private copy) for files in a location others can write.
- **Write through `tula_builder_add_long`** (1.3.0) or
  `tula_builder_add_checked` (1.2.0). The plain add truncates names over 47
  characters (frozen v1 behaviour), so two distinct long names can become the
  same stored name. The LoRA pair `…q_proj.lora_A.weight` /
  `…q_proj.lora_B.weight` under a `base_model.model.model.layers.N.self_attn.`
  prefix does, and `tula_find` returns the first match. `add_long` stores long
  names whole in the names table (ADR 0004) and refuses repeats;
  `add_checked` refuses long names outright. **Look up by `tula_find_name`**,
  which verifies the full name, so a key collision can't hand back the wrong
  tensor.
- **Manage your own keys.** Use a trustworthy source for `sk`/`pk`.

## Reporting a vulnerability

Report suspected vulnerabilities privately to the maintainer
(<robert.maccracken@gmail.com>) rather than opening a public issue. Please
include a reproduction (a crafted file or a failing `tula_validate` case) and the
Cyrius toolchain version. Audits live in [`docs/audit/`](docs/audit/): the
latest is [2026-11-04](docs/audit/2026-11-04-audit.md) (P(-1), 1.1.2); the
first is [2026-07-01](docs/audit/2026-07-01-audit.md).
