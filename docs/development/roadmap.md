# tula — Roadmap

Pre-1.0; the public surface moves until v1.0 (no API freeze before then).

## M0 — format + in-memory round-trip ✅ (v0.1.0, unreleased)
- Header + typed manifest + payload; dtype f64/int8/ternary/nf4.
- Builder (serialize) + reader (validate + accessors) + find-by-name.
- `programs/smoke.cyr` link-check; `tests/tcyr/roundtrip.tcyr` — **22 assertions**.

## M0b — sigil-signed header (the trust boundary) ✅ (v0.1.0, unreleased)
- `[deps.sigil]` wired; Ed25519 sign over the content `[0..sig_off)` (header incl.
  sig fields ‖ manifest ‖ payload); signature appended at `sig_off`.
- `tula_builder_finish_signed(b, sk)` + `tula_verify(r, pk)` →
  `TULA_SIG_OK`/`TULA_SIG_BAD`/`TULA_SIG_UNSIGNED`; `tula_is_signed(r)` presence check.
- `tests/tcyr/sign.tcyr` (**8 assertions**): sign→verify OK, tampered-payload →
  BAD, wrong-key → BAD, unsigned → UNSIGNED.
- CI + release workflows added; **0.1.0 tag ready to cut** (M0 milestone complete).

## M1 — file I/O
- `tula_write_file` (serialize → disk) + `tula_open_file` (mmap read, zero-copy).
- Round-trip an **attn11 checkpoint** through a real file, bit-identical;
  `e2`-style integrity check.

## M2 — dtype payload helpers
- Ternary pack/unpack (tentib interop) + NF4 block layout (anukulana/QLoRA
  interop) as payload conventions the codec understands (offsets/scales in the
  manifest as needed).

## v1.0 — freeze
- Public API frozen + `docs/api.md`; in-tree fuzz harness (malformed header /
  lying manifest / truncation) + a bench harness; `SECURITY.md`; ≥1 downstream
  consumer green (rupantara/anukulana or the murti load-seam).

## Gates / relations
- CPU-only, no GPU. sigil required at M0b. Consumed by `rupantara` /
  `anukulana` / murti-seam / control-plane store. See the AGNOS planning docs
  `type3-weight-import.md` + `software-port-path.md`.
