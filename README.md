# tula

**तुला — balance / scale; the instrument that weighs.**

`tula` is AGNOS's **sovereign weight-file format** — a typed, mmap-friendly
tensor manifest + payload with a **sigil-signable header**. It is the
safetensors/GGUF analog behind the Type-3 pretrained-import path, written in
pure Cyrius with no external code.

It is the on-disk form that AGNOS-trained checkpoints (attn11, tentib ternary),
imported foreign models, and control-plane checkpoints all take. It is **not** a
model store (that is the control-plane's, over vahana/sankoch + sigil) and
**not** the importer (that is [`anukulana`](https://github.com/MacCracken/anukulana), the Type-3 reference) — tula is only
the codec.

## Format

```
HEADER (64 bytes)                MANIFEST (count × 144-byte entries)      PAYLOAD
  +0  magic  "TULA"                +0   name[48]  (cstring, null-padded)    raw tensor
  +8  version                      +48  dtype     (f64|int8|ternary|nf4)    bytes, each
  +16 tensor_count                 +56  ndim                                8-byte aligned
  +24 manifest_off (=64)           +64  shape[8]
  +32 payload_off                  +128 data_off  (within payload)
  +40 payload_len                  +136 data_len
  +48 sig_off  (0 = unsigned)
  +56 sig_len  (0 = unsigned)
```

All fields are i64-aligned little-endian words. The header reserves
`sig_off`/`sig_len` for the sigil-signed trust boundary (wired in M0b).

## Status

**1.0.0 — API frozen** (`docs/api.md` + `STABILITY.md`; on-disk format **v1**).
The full march M0→M5:

- **M1** file I/O — `tula_write_file` / `tula_read_file` (heap) / `tula_open_mmap`
  (zero-copy) / `tula_close_mmap`; self-describing (no `stat()`).
- **M2** dtype payload helpers — ternary / int8 / NF4 pack/unpack; scales ride in
  a `"<name>.scale"` sidecar tensor (ADR 0002 — no format-version bump).
- **M3** reader hardening — `tula_validate` + a strict `tula_open` reject
  untrusted/lying/truncated input (overflow-safe, resource-capped).
- **M4** fuzz (2M+ iters clean) + bench (`docs/benchmarks.md`).
- **M5** security audit (`docs/audit/`, PASS) + `SECURITY.md`.
- **v1.0 prep** — `docs/api.md` (frozen surface) + `STABILITY.md` +
  `examples/consumer.cyr` (end-to-end, CI gate).

- **1.1.2 P(-1)** — hardening / optimization / repair (`docs/audit/2026-11-04-audit.md`):
  file readers check the header against the real file size; hot paths 1.2–11.6×
  faster, byte-identical output.

- **1.2.0** — real checkpoints, checked: `tula_builder_new_cap`,
  `tula_builder_add_checked`, `tula_validate_strict` (canonical layout, unique
  names, shape ↔ size), `tula_verify_required`, `tula_find_scale`,
  `tula_entry_nelems`.

- **1.3.0** — real names, real dtypes: tensor names of any length via the
  `__tula.names__` table (`tula_builder_add_long`, `tula_find_name`), and
  `TULA_DT_F32/F16/BF16` with exact IEEE conversions. Still format v1.

- **1.4.0** — big files: `tula_builder_write_file(_signed)` streams checkpoints of
  any size straight from tensor buffers and replaces the target atomically;
  `tula_read_file_into` reads them into a buffer of your own.

- **1.5.0** — lookup at scale: a name index (`tula_index_new` / `tula_index_find`)
  with O(log n) lookups that crafted names can't degrade, and a CI gate running
  five real checkpoint inventories (GPT-2, Llama-2-7B, Mixtral-8x7B, LoRA, QLoRA)
  end to end.

- **1.6.0** — file metadata: signed key/value text (`tula_builder_set_meta`,
  `tula_meta_get`) for the architecture, config and provenance, in a table every
  1.x reader opens.

- **1.6.1** — on Linux the streaming writers build the file nameless
  (`O_TMPFILE`) and name it only once it is signed; the writers are fuzzed
  against the in-memory writer; CI runs on aarch64 Linux and macOS too.

- **1.6.2** — macOS is a hard gate; `tula_write_file(_atomic)` handle buffers
  over 2 GiB there too.

- **1.7.0** — integer and boolean dtypes: `TULA_DT_I16/I32/I64/U8/BOOL`, stored
  raw, so ids, masks, buffers and GPTQ's packed int32 tensors keep their types.
  Strict rejects a BOOL byte other than 0 or 1 (`TULA_ERR_VALUE`). The
  real-model gate gains a GPTQ inventory.

- **1.8.0** — compact formats: OCP FP8 (`TULA_DT_F8_E4M3` / `F8_E5M2`, exact,
  non-saturating conversions, checked on every code and midpoint) and `TULA_DT_INT4`
  (signed 4-bit codes with a `.scale` sidecar, quantized by Q4_0's rule).

- **1.9.0** — throughput: the array helpers are 1.4–6.7× faster with the same
  output, and `tula_unpack_par` splits an unpack across threads (~1–2 Gelem/s
  at 8 threads); strict validation, adds and short-name lookups cost less per
  call.

- **1.9.1** — NF4 packing 2.6× faster (exact thresholds instead of a codebook
  scan) and F16 / BF16 unpacking 1.75× faster on large tensors, with the same
  output.

- **1.10.0** — a protected open: `tula_open_protected` gives a reader that no
  later rewrite or truncation of the file can reach, zero-copy for fs-verity
  files and a private copy otherwise.

- **1.11.0** — sharded checkpoints: a shard set binds a model's files with a
  signed manifest of their SHA-256, and `tula_set_open` verifies it in parallel
  (~1.2 GB/s at 8 threads, against 17 MB/s per signed file) and resolves names
  across it.

- **1.12.0** — asymmetric 4-bit: `TULA_DT_UINT4` with `.scale` and `.min`
  sidecars stores GGUF Q4_1 losslessly, and `tula_find_sidecar` finds a sidecar
  by any suffix.

**974/974** assertions across 19 suites (meta · shards · fp8 · names · stream ·
builder · strict · ints · uint4 · dtype · int4 · kernels · floats · protected ·
file-io · hardening · round-trip · index · sign) + a
>3·10⁶-iteration guard-page fuzz harness (which also checks the streaming
writers against the in-memory one), an end-to-end consumer, a real-model
inventory gate and a 2.36 GB big-file gate, all green on x86_64 Linux and on
aarch64 Linux under qemu. CI adds native aarch64 Linux and macOS runners, both
hard gates. Deps: stdlib + **sigil**
(Ed25519); the cyrius pin lives in `cyrius.cyml`. CI + release workflows in
place. Post-1.0 changes are additive-only (SemVer). See
[`docs/api.md`](docs/api.md) and [`docs/development/roadmap.md`](docs/development/roadmap.md).

## Build & test

```sh
make build    # link-check the library via programs/smoke.cyr
make test     # run tests/tcyr/*.tcyr (15 suites)
make dist     # regenerate dist/tula.cyr for consumers
make example  # build + run the end-to-end consumer (examples/consumer.cyr)
make fuzz     # reader + streaming-writer fuzz harness (>10^6 iters)
make bench    # write/read/mmap throughput -> docs/benchmarks.md
```

## Documentation

- **[Getting started](docs/guides/getting-started.md)** — build, test, write/read
  a weight file, consume the bundle. More how-tos in [`docs/guides/`](docs/guides/).
- **[API reference](docs/api.md)** — the frozen public surface · **[STABILITY.md](STABILITY.md)** — the post-1.0 contract.
- **[Examples](docs/examples/)** — runnable code ([`examples/consumer.cyr`](examples/consumer.cyr)).
- **[Decisions](docs/adr/)** (ADRs) · **[Code invariants](docs/architecture/)** (architecture notes).
- **[Security](SECURITY.md)** + **[audit](docs/audit/)** · **[Benchmarks](docs/benchmarks.md)**.
- **[Roadmap](docs/development/roadmap.md)** · **[State](docs/development/state.md)** · **[Contributing](CONTRIBUTING.md)**.

## Consumers (planned)

`rupantara` + `anukulana` (Type-3 pretrained-import), the murti load-seam, and
the control-plane checkpoint store — all pull `dist/tula.cyr` via a
`[deps.tula]` git-tag entry. See the AGNOS planning docs
`type3-weight-import.md` and `software-port-path.md`.

## License

GPL-3.0-only.
