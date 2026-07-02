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

**M0 (v0.1.0, unreleased):** in-memory serialize → parse round-trip, bit-identical;
magic/version validation; find-by-name; dtype/shape/payload accessors. **22/22**
assertions green. File I/O (mmap read / write-to-disk) and the sigil-signed
header are the next bites — see [`docs/development/roadmap.md`](docs/development/roadmap.md).

Pure Cyrius, no external deps (M0 is stdlib-only). Cyrius pin **6.3.26**.

## Build & test

```sh
make build    # link-check the library via programs/smoke.cyr
make test     # run tests/tcyr/*.tcyr (M0 round-trip)
make dist     # regenerate dist/tula.cyr for consumers
```

## Consumers (planned)

`rupantara` + `anukulana` (Type-3 pretrained-import), the murti load-seam, and
the control-plane checkpoint store — all pull `dist/tula.cyr` via a
`[deps.tula]` git-tag entry. See the AGNOS planning docs
`type3-weight-import.md` and `software-port-path.md`.

## License

GPL-3.0-only.
