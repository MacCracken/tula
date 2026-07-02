# Changelog

All notable changes to `tula` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is SemVer
(pre-1.0 — the public surface is still moving, no API freeze until v1.0).

## [0.1.0] — Unreleased

**M0 — the format + in-memory round-trip.** First cut of the sovereign
weight-file format.

### Added
- Weight-file format: 64-byte header (magic/version/count/offsets +
  reserved `sig_off`/`sig_len`) + typed 144-byte manifest entries
  (name[48] / dtype / ndim / shape[8] / data_off / data_len) + 8-byte-aligned
  payload. All fields i64-aligned. (`src/format.cyr`)
- `dtype` set: `f64`, `int8`, `ternary`, `nf4`.
- Builder API: `tula_builder_new` / `tula_builder_add` / `tula_builder_finish`
  serialize tensors into one contiguous buffer.
- Reader API: `tula_open` (magic + version validation) + accessors
  (`tula_count`, `tula_entry`, `tula_entry_{name,dtype,ndim,dim,data,data_len}`,
  `tula_find`, `tula_total_len`, `tula_sig_status`).
- Error codes + name lookup (`src/error.cyr`).
- `programs/smoke.cyr` link-check; `tests/tcyr/roundtrip.tcyr` M0 suite
  (**22 assertions**: bit-identical round-trip of an f64 [2,3] and an int8 [4]
  tensor, bad-magic + short-buffer rejection, find, version int).

### Notes
- M0 is **in-memory** (serialize → parse). File I/O (mmap read / write-to-disk)
  and the **sigil-signed header** (`sig_off`/`sig_len` are reserved; files are
  unsigned in M0) are the next bites — see `docs/development/roadmap.md`.
- Pure Cyrius, stdlib-only deps. Cyrius pin **6.3.26**.
