# Changelog

All notable changes to `tula` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is SemVer. As of
**v1.0** the public surface is frozen — see [`STABILITY.md`](STABILITY.md)
(format v1 stable; MINOR = additive-only; MAJOR = format/API break).

## [Unreleased]

## [1.0.0] — 2026-07-01

**v1.0 — API freeze.** The codec surface is frozen (`docs/api.md` +
`STABILITY.md`); the on-disk format is **v1**. The march from 0.1.0: file I/O,
dtype payload helpers, reader hardening (the untrusted-input trust gate), fuzz +
bench, and a security audit — with a green end-to-end downstream consumer.

### Added
- **First-party documentation scaffold** (per the AGNOS first-party doc standard).
  Root files completed: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (all seven required
  root files now present). `docs/` filled to the standard: `docs/guides/`
  (`README.md` + `getting-started.md`), `docs/architecture/` (`README.md` +
  `001-flat-module-layout.md` + `002-accessors-require-validated-buffer.md`),
  `docs/examples/README.md` (indexes the root `examples/`),
  [ADR 0003](docs/adr/0003-api-freeze-at-v1.md) recording the 1.0 API + format-v1
  freeze decision, and `docs/sources.md` citing the quantization schemes (NF4 →
  QLoRA/bitsandbytes, ternary → BitNet b1.58, int8 → LLM.int8(), Ed25519 → RFC
  8032) with an inline citation on `tula_nf4_level`. `CLAUDE.md` de-staled: a
  durable pointer block (→ `state.md` / `CHANGELOG` / `api.md`) + a docs pointer
  replace the old inline roadmap/version.
- **v1.0 prep — freeze docs + downstream consumer.** `docs/api.md` documents the
  frozen public surface (format spec, builder, reader, sign, file-I/O, dtype
  helpers, error/dtype/sig constants). `STABILITY.md` states the post-1.0 policy
  (format v1 frozen; MINOR = additive-only; MAJOR = format/API break; internal
  helpers + cap values excluded). `examples/consumer.cyr` (`make example`) — a
  complete end-to-end consumer: ternary-quantize → build + scale sidecar → sign →
  write → read (untrusted) → verify → `tula_entry_payload_ok` guard → unpack →
  dequant, plus a bit-exact f64 tensor; runs green and is a **CI gate**. CI lint
  + fmt-check now also cover `examples/`.
- **M5 — security audit + `SECURITY.md`**. Six-dimension audit
  (`docs/audit/2026-07-01-audit.md`): memory safety · integer overflow ·
  untrusted-input bounds · signature-verify correctness (sigil canonical-`S`
  reject + `ct_eq` compare) · resource caps · fail-loud — **verdict PASS**. One
  consumer-side over-read sharp edge (a lying `shape` vs a smaller `data_len`)
  found and **closed**: new `tula_packed_len(dtype, nelems)` +
  `tula_entry_payload_ok(e)` (`src/dtype.cyr`) — an overflow-safe one-line guard a
  foreign-checkpoint consumer runs before any unpack. `SECURITY.md` documents the
  threat model (reader = trust boundary; signed header = authenticity boundary via
  sigil; keys are the caller's; writer is trusted). `dtype.tcyr` +8 (now 29).
  Suite total now **105**.
- **M4 — fuzz + bench harnesses**. `programs/fuzz.cyr` (`make fuzz`): a
  deterministic-LCG fuzzer that floods `tula_open` + every accessor + `tula_verify`
  with mutated + random bytes — **2,003,000 iterations** (>10⁶) clean, asserting
  no crash and that every *accepted* buffer is genuinely sound (re-validation
  agrees; every entry's payload range stays inside `[buf, buf+len)`). Validates
  the M3 hardening. `programs/bench.cyr` (`make bench`): write/read/mmap
  throughput on a ~100 MB synthetic file (200 tensors); numbers + method in
  `docs/benchmarks.md`. `make fuzz` / `make bench` targets added.
- **M3 — reader hardening** (`src/format.cyr`): `tula_validate(buf, len)` — the
  untrusted-input trust gate. Validates every structural invariant against the
  buffer length (magic/version, `manifest_off == 64`, `payload_off == 64 +
  count*ENTRY_SIZE ≤ len`, `payload_off+payload_len ≤ len`, per-entry `ndim ≤ 8`,
  NUL-terminated names, `data_off+data_len ≤ payload_len`, sig-field consistency)
  with overflow-safe arithmetic, and rejects with a specific `TULA_ERR_*` code.
  **`tula_open` now runs full validation** (was magic+version only), so untrusted
  files can never OOB-deref. `sig_len` is pinned to {0, 64} so `tula_verify`'s
  fixed 64-byte read can never escape the buffer. Resource caps
  (`TULA_READ_MAX_TENSORS` = 2²⁰, `TULA_READ_MAX_BYTES` = 2⁴⁰) bound arithmetic
  and guard against bomb-sized headers; `tula_read_file`/`tula_open_mmap`
  sanity-check the header total (`tula_hdr_total`) **before** allocating/mmap'ing.
- New error codes: `TULA_ERR_BOUNDS` (9), `TULA_ERR_NDIM` (10), `TULA_ERR_HEADER`
  (11), `TULA_ERR_TOO_BIG` (12), with names in `tula_err_name`.
- `tests/tcyr/hardening.tcyr` (**30 assertions**): bad magic/version, len<header,
  truncated payload, over-/negative-count, payload-len bomb, lying + overflowing
  entry offsets, out-of-range ndim, unterminated name, sig-field inconsistency
  (wrong offset / non-{0,64} length / cut-short signature), and pure-garbage —
  all rejected with the right code, no crash. Existing suites stay green under the
  stricter `tula_open`. Suite total now **97**.
- **M2 — dtype payload helpers** (`src/dtype.cyr`): pure pack/unpack transforms
  for the quantized dtypes. **Ternary** {−1,0,+1} ↔ 2-bit packed codes
  (`tula_ternary_pack`/`_unpack`/`_get`/`_bytes`; mirrors tentib's `tpack2`).
  **int8** per-tensor absmax (`tula_int8_quant` returns the f64 scale /
  `tula_int8_dequant`). **NF4** 4-bit blockwise NormalFloat (`tula_nf4_pack`/
  `_unpack`/`_get`/`_nearest`/`_level`/`_blocks`/`_bytes`; the 16-entry QLoRA
  codebook as f64 bit patterns, per-block absmax scales, div-by-zero-safe
  zero-blocks). Double-quant composes for free (int8-quantize the scale sidecar).
- **ADR 0002** — quantization **scales are sidecar `"<name>.scale"` tensors**,
  not an entry field: no `TULA_VERSION`/`TULA_ENTRY_SIZE` bump (the 144B entry
  stays frozen), scales stay first-class introspectable f64 tensors whose shape
  expresses granularity (scalar / per-row / per-block). Rejected option (a) —
  a single entry field can't hold NF4's per-block scale *array*.
- `tests/tcyr/dtype.tcyr` (**21 assertions**): ternary exact round-trip +
  accessor agreement, int8 within-a-quantum + signed-rail, NF4 within
  half-gap·absmax over two distinct-scale blocks, zero-block safety, and a full
  build→write→read of a ternary tensor **+ its `.scale` sidecar**. Suite total
  now **67**.
- **M1 — file I/O** (`src/fileio.cyr`): `tula_write_file` (serialize→disk),
  `tula_read_file` (read back into a heap buffer; validates magic/version),
  `tula_open_mmap` (zero-copy read-only mmap) + `tula_close_mmap`. tula files are
  self-describing (the header carries the total length), so reads need no `stat()`.
- `tests/tcyr/fileio.tcyr` (**16 assertions**): write→read bit-identical, signed
  file survives + verifies, mmap round-trip, missing-file → 0. Suite total now **46**.

## [0.1.0] — 2026-07-01

**M0 + M0b — the weight-file format, round-trip, and the sigil-signed header.**
First cut of the sovereign weight-file format with an Ed25519 trust boundary.

### Added
- **Format** (`src/format.cyr`): 64-byte header (magic/version/count/offsets +
  `sig_off`/`sig_len`) + typed 144-byte manifest entries (name[48] / dtype /
  ndim / shape[8] / data_off / data_len) + 8-byte-aligned payload. All fields
  i64-aligned. `dtype` set: `f64`, `int8`, `ternary`, `nf4`.
- **Builder / reader**: `tula_builder_new` / `tula_builder_add` /
  `tula_serialize` / `tula_builder_finish` (unsigned); `tula_open` (magic +
  version validation) + accessors (`tula_count`, `tula_entry`,
  `tula_entry_{name,dtype,ndim,dim,data,data_len}`, `tula_find`,
  `tula_total_len`, `tula_is_signed`).
- **Signed header (M0b, `src/sign.cyr`)**: Ed25519 sign/verify over the file
  content `[0..sig_off)` (header incl. the sig fields ‖ manifest ‖ payload),
  signature appended at `sig_off`. `tula_builder_finish_signed(b, sk)` +
  `tula_verify(r, pk)` → `TULA_SIG_OK` / `TULA_SIG_BAD` / `TULA_SIG_UNSIGNED`.
  Crypto is **sigil** (Ed25519); keys are the caller's (tula owns no key mgmt).
- Error codes + name lookup (`src/error.cyr`).
- `programs/smoke.cyr` link-check; **30 assertions** across 2 suites —
  `tests/tcyr/roundtrip.tcyr` (22: bit-identical round-trip, bad-magic +
  short-buffer rejection, find, version) and `tests/tcyr/sign.tcyr` (8:
  sign→verify OK, tampered-payload → BAD, wrong-key → BAD, unsigned → UNSIGNED).
- **CI** (`.github/workflows/ci.yml`): build+test, lint, fmt-check, vet,
  dist-sync, ELF check, security scan, docs/version consistency.
- **Release** (`.github/workflows/release.yml`): on a `0.1.0` (or `v0.1.0`) tag —
  CI gate → build/test → regenerate `dist/tula.cyr` → archive (src tarball +
  `tula.cyr` + SHA256SUMS) → GitHub release (flagged pre-release for 0.x).

### Notes
- File I/O (mmap read / write-to-disk, round-trip a real attn11 checkpoint file)
  is the next bite (M1) — see `docs/development/roadmap.md`.
- Deps: stdlib + **sigil** (Ed25519). Local dev resolves sigil via
  `path = "../sigil"`; **CI/release resolve it via `[deps.sigil]` git+tag, so
  the sigil tag (3.9.9) must exist on GitHub** for CI + the 0.1.0 release.
- Cyrius pin **6.3.27**.
