# Changelog

All notable changes to `tula` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/); this project is SemVer
(pre-1.0 — the public surface is still moving, no API freeze until v1.0).

## [0.1.0] — Unreleased

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
