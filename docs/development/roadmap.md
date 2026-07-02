# tula — Roadmap (march to v1.0)

> **For a secondary agent picking this up cold.** This is a self-contained plan.
> Read this + `CLAUDE.md` (conventions) + `docs/adr/0001-tula-scope.md` (scope)
> and you have everything. tula is the sovereign weight-file **codec** — not a
> store, not the importer, not a tensor lib (ADR 0001). Pre-1.0: the public
> surface may still move, **no API freeze until v1.0**.

---

## Working agreement (read before touching code)

- **Build/test:** `make build` (link-check via `programs/smoke.cyr`), `make test`
  (globs `tests/tcyr/*.tcyr`), `make dist` (regenerate `dist/tula.cyr`).
  Cyrius pin lives in `cyrius.cyml` (`cyrius = "..."`) — the single source of truth.
- **Flat modules:** stdlib `include`s live **only** in `src/lib.cyr`; `src/*.cyr`
  domain modules are flat (no includes) so `cyrius distlib` concatenates a
  compile-clean `dist/tula.cyr`. New module → add to `src/lib.cyr` **and**
  `cyrius.cyml [lib].modules` (dependency order). The LSP will flag cross-module
  symbols as "undefined" in a standalone file — that's the flat-module pattern,
  resolved through `lib.cyr`; ignore it, the build is authoritative.
- **Definition of done, every bite:** `make test` green · `cyrius fmt <files>`
  clean (CI gate) · `cyrius lint` no `warn ` lines · `make dist` regenerated &
  committed (CI dist-sync gate) · CHANGELOG `[Unreleased]` updated.
- **Do NOT** bump `VERSION` or `git` anything — the maintainer cuts releases
  (bump VERSION → rename CHANGELOG `[Unreleased]` → `[x.y.z]` → tag). New work
  accretes under `[Unreleased]`.
- **`sigil` dep:** local dev resolves via `path = "../sigil"`; CI via git+tag —
  a sigil tag must exist on GitHub for CI/release.

## Format invariants (don't break casually)

On-disk layout (all fields i64-aligned LE). Consumers depend on it; a change =
a format-version bump (`TULA_VERSION`) + reader back-compat consideration.

- **Header (64B):** `+0` magic `+8` version `+16` count `+24` manifest_off(=64)
  `+32` payload_off `+40` payload_len `+48` sig_off(0=unsigned) `+56` sig_len.
- **Entry (144B):** `+0` name[48] `+48` dtype `+56` ndim `+64` shape[8] `+128`
  data_off `+136` data_len.
- **Signature:** Ed25519 over content `[0..sig_off)`, appended at `sig_off`.

---

## Shipped (0.1.0 + `[Unreleased]`)

- **M0 ✅** format + in-memory round-trip (builder/reader/find). `roundtrip.tcyr` (22).
- **M0b ✅** Ed25519 signed header via sigil (`sign`/`verify`/`is_signed`). `sign.tcyr` (8).
- **M1 ✅** file I/O: `tula_write_file` / `tula_read_file` (heap) / `tula_open_mmap`
  (zero-copy) / `tula_close_mmap`. `fileio.tcyr` (16).
- **M2 ✅** dtype payload helpers (`src/dtype.cyr`): ternary 2-bit (mirrors tentib
  `tpack2`), int8 absmax quant/dequant, NF4 4-bit blockwise (QLoRA codebook +
  per-block absmax). Scale decision resolved (**ADR 0002**): scales are sidecar
  `"<name>.scale"` tensors — **no format-version bump**. `dtype.tcyr` (21).
- **M3 ✅** reader hardening (`src/format.cyr`): `tula_validate` + a strict
  `tula_open` reject untrusted/lying/truncated input with a specific `TULA_ERR_*`,
  overflow-safe, resource-capped (`TULA_READ_MAX_TENSORS`/`_BYTES`); file readers
  bomb-guard the header total before alloc/mmap. `hardening.tcyr` (30).
  **Suite total: 97.**
- **M4 ✅** fuzz + bench harnesses. `programs/fuzz.cyr` (`make fuzz`): 2M+
  deterministic-LCG iterations through `tula_open` + accessors + `tula_verify`,
  clean — no crash, every accepted buffer sound (validates M3). `programs/bench.cyr`
  (`make bench`) + `docs/benchmarks.md`: write/read/mmap on a ~100 MB file.
- **M5 ✅** security audit + `SECURITY.md`. 6-dimension audit
  (`docs/audit/2026-07-01-audit.md`, verdict **PASS**); closed a consumer-side
  over-read (`tula_packed_len` + `tula_entry_payload_ok`, `dtype.tcyr` +8 → 29).
  `SECURITY.md` threat model (reader = trust boundary; signed header =
  authenticity via sigil; keys are the caller's). **Suite total: 105.**

---

## Remaining milestones

### v1.0 — freeze & clean cut ✅ (ready; awaiting the maintainer's cut)
- **`docs/api.md`** ✅ documents the frozen public surface (format spec + builder/
  reader/sign/file-io/dtype + constants); **`STABILITY.md`** ✅ (format v1 frozen;
  MINOR additive-only; MAJOR = format/API break).
- **≥1 downstream consumer green** ✅ — `examples/consumer.cyr` (`make example`):
  quantize → build+sidecar → sign → write → read (untrusted) → verify → payload
  guard → unpack → dequant, end-to-end; wired as a **CI gate**.
- All v1.0 criteria checked (below); CHANGELOG complete. **Remaining = the
  maintainer's action only**: bump `VERSION → 1.0.0`, rename `[Unreleased]` →
  `[1.0.0]`, tag (+ ensure the `sigil` tag exists for CI/release).

---

## v1.0 criteria (the checklist)

- [x] Public API frozen + documented (`docs/api.md` + `STABILITY.md`)
- [x] Full test coverage (round-trip · sign · file-io · dtype · **hardening**) — 105 assertions
- [x] Fuzz harness clean (≥10^6 iters) — 2,003,000 iters, malformed/lying/truncated rejected
- [x] Bench harness + `docs/benchmarks.md` (write/read/mmap at scale)
- [x] Security audit report + `SECURITY.md` (`docs/audit/2026-07-01-audit.md`, PASS)
- [x] ≥1 downstream consumer green (`examples/consumer.cyr`, CI gate)
- [x] CHANGELOG complete; version consistency (VERSION stays 0.1.0 until the maintainer's cut)

---

## Gates / relations

- **CPU-only, no GPU.** `sigil` is the one external (sovereign) dep.
- **Consumers:** `rupantara` / `anukūlana` (Type-3 pretrained-import), the murti
  load-seam, the control-plane checkpoint store — all pull `dist/tula.cyr` via
  `[deps.tula]`. Keep the format stable for them; a format bump is a coordinated
  event.
- **Ecosystem context:** the AGNOS planning docs `type3-weight-import.md`
  (gap #1) + `software-port-path.md` (Tier A). tula is gap #1's format codec.
