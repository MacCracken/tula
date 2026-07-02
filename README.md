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

**0.1.0 released** (M0 + M0b: format + round-trip + Ed25519 signed header). The
`[Unreleased]` line is **feature-complete for v1.0** and awaiting the maintainer's
cut:

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

**105/105** assertions across 5 suites (round-trip · sign · file-io · dtype ·
hardening). Deps: stdlib + **sigil** (Ed25519). Cyrius pin **6.3.27**. CI +
release workflows in place. VERSION stays 0.1.0 until the maintainer's cut. See
[`docs/api.md`](docs/api.md) and [`docs/development/roadmap.md`](docs/development/roadmap.md).

## Build & test

```sh
make build    # link-check the library via programs/smoke.cyr
make test     # run tests/tcyr/*.tcyr (5 suites)
make dist     # regenerate dist/tula.cyr for consumers
make example  # build + run the end-to-end consumer (examples/consumer.cyr)
make fuzz     # reader fuzz harness (>10^6 iters)
make bench    # write/read/mmap throughput -> docs/benchmarks.md
```

## Consumers (planned)

`rupantara` + `anukulana` (Type-3 pretrained-import), the murti load-seam, and
the control-plane checkpoint store — all pull `dist/tula.cyr` via a
`[deps.tula]` git-tag entry. See the AGNOS planning docs
`type3-weight-import.md` and `software-port-path.md`.

## License

GPL-3.0-only.
