# tula — Roadmap

> **For a secondary agent picking this up cold.** Read this + `CLAUDE.md`
> (conventions) + `docs/adr/0001-tula-scope.md` (scope) + `STABILITY.md` (what a
> 1.x release may change). tula is the sovereign weight-file **codec** — not a
> store, not the importer, not a tensor lib (ADR 0001). The public surface and
> on-disk format v1 are **frozen** (ADR 0003): every 1.x MINOR below is
> **additive only** (new functions, new `TULA_ERR_*` / `TULA_DT_*` values, new
> sidecar conventions under an ADR); a layout change is v2.
>
> This file is **future work only**. What shipped is in
> [`CHANGELOG.md`](../../CHANGELOG.md), where things stand now in
> [`state.md`](state.md), and why in [`docs/adr/`](../adr/).

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
  clean (CI gate) · `cyrius lint` no `warn ` lines · `cyrius doc --check src/*.cyr`
  0 undocumented · `cyrius deny programs/smoke.cyr` clean · `make fuzz` PASS ·
  `make realmodels` and `make bigfile` PASS (CI gates, also on the
  `cross-target` runners) · `make dist` regenerated &
  committed (CI dist-sync gate) · CHANGELOG `[Unreleased]` updated. A speed change
  also gets a differential test against the old code and before/after
  `make bench` numbers in `docs/benchmarks.md`. A new public behaviour gets a
  cross-version byte diff showing every existing call's output is unchanged.
- **Do NOT** bump `VERSION` or `git` anything unless the maintainer asks — the
  maintainer cuts releases (bump VERSION → rename CHANGELOG `[Unreleased]` →
  `[x.y.z]` → tag). New work accretes under `[Unreleased]`.
- **`sigil` dep:** every build resolves git+tag, local and CI alike; the sigil tag
  must exist on GitHub. `path = "../sigil"` is read only in local mode
  (`CYRIUS_LOCAL=1` / `--local`), to build against a sigil working tree.
- **Cross-repo facts** (what a consumer pins, its toolchain) go stale. Read the
  other repo's `cyrius.cyml` at the moment you cite it, or leave the version out.

## Format invariants (don't break casually)

On-disk layout (all fields i64-aligned LE). Consumers depend on it; a change =
a format-version bump (`TULA_VERSION`) + reader back-compat consideration.

- **Header (64B):** `+0` magic `+8` version `+16` count `+24` manifest_off(=64)
  `+32` payload_off `+40` payload_len `+48` sig_off(0=unsigned) `+56` sig_len.
- **Entry (144B):** `+0` name[48] `+48` dtype `+56` ndim `+64` shape[8] `+128`
  data_off `+136` data_len.
- **Signature:** Ed25519 over content `[0..sig_off)`, appended at `sig_off`.
- **v1 conventions** (frozen as the layout is):
  - quantization scales as `"<name>.scale"` sidecar tensors (ADR 0002);
  - long names through the trailing `__tula.names__` table and 47-byte keys
    (ADR 0004);
  - the F32/F16/BF16 encodings and their rounding (ADR 0005);
  - file metadata through the `__tula.meta__` table, before the names table
    (ADR 0008);
  - the raw integer encodings and BOOL's 0/1 rule (ADR 0009);
  - the FP8 encodings and conversion semantics (ADR 0010), and INT4's nibble
    order, unused-nibble rule and quantization rule (ADR 0011).

  A new convention (a reserved tensor, a naming rule) is a MINOR with its own
  ADR, and must stay readable by every older 1.x reader.

---

## 1.6.x — the write path follow-through

**Goal:** the write path's remaining loose ends, and the real-weights gate.

- **1.6.x patches** (no new surface — a patch never adds a function, dtype or
  convention): fixes as the cross-target legs and consumers turn them up. CI's
  aarch64 Linux and arm64 macOS legs are both hard gates (macOS since 1.6.2).
  x86_64 macOS isn't covered: GitHub's hosted Intel runners are scarce.
- **Cross-repo** (not tula code):
  - **anukulana's migration**, which makes its `gpt2-tula` demo the
    real-weights gate. That demo already imports the real GPT-2 checkpoint,
    NF4-quantizes it, saves a signed tula file, reloads it and checks the result
    bit for bit. It needs anukulana on the current toolchain and tula, and the
    checkpoint staged in its CI. tula's own CI can't run it without depending on
    its consumer, so `make realmodels` covers tula's side.
  - **Other consumers** move onto the 1.2–1.6 calls (checked / long adds,
    strict reads, streaming writes, the index, metadata), as
    `examples/consumer.cyr` shows.

## 1.7.x — integer and boolean dtypes

**Goal:** an importer can store every tensor of a real checkpoint losslessly.
1.7.0 adds `I16` / `I32` / `I64` / `U8` / `BOOL` (ADR 0009, codes 7–11).

- **1.7.x patches** — fixes as importers store full checkpoints; no new surface.
  U16/U32/U64 and element-read helpers wait for a consumer that needs them (a
  MINOR; ADR 0009 says why they were left out).

## 1.8.x — compact formats: FP8 and int4

**Goal:** the compact formats real checkpoints and quantized imports use. 1.8.0
adds OCP FP8 `F8_E4M3` / `F8_E5M2` (ADR 0010, codes 12–13) and `INT4`, signed
codes with an ADR 0002 `.scale` sidecar (ADR 0011, code 14).

- **1.8.x patches** — fixes; no new surface. Left for a MINOR when an importer
  needs them (the ADRs say why): saturating FP8 conversions, the FNUZ FP8
  variants, an unsigned 4-bit dtype for asymmetric schemes (Q4_1, AWQ/GPTQ zero
  points) and its `.min` / zero-point sidecar convention. New codes start at 15.

## 1.9.x — throughput

**Goal:** the codec is never the slow part of loading a model. Every change gets
a differential test and before/after numbers (`docs/benchmarks.md` has today's).
1.9.0 made the array helpers faster with the same output bit for bit: table
paths for the byte and nibble formats, and one loop per float format. It also
added `tula_unpack_par` (ADR 0012, `src/par.cyr`) and cut the per-call costs of
validation, adds and index lookups.

- **1.9.x patches** — faster kernels and smaller per-call costs change no API,
  so they can ship as patches. 1.9.1 made NF4 pack search 15 exact thresholds
  instead of scanning the codebook, and gave the F16 / BF16 unpacks a per-call
  table from 262,144 elements. What's left measured as not worth it:
  - INT4 **pack** is bound by its per-element f64 division and floor; writing
    whole bytes instead of nibbles gained ~15%.
  - The F32 unpack (~218 Melem/s) has no table (2³² codes), and unrolling the
    float loops by 2 or 4 gained nothing under cyrius's code generation.
- **Left for a MINOR when a consumer needs it** (ADR 0012 says why):
  - a parallel pack (INT8's per-tensor absmax needs a reduction across
    threads);
  - a caller-owned worker pool, if per-call thread starts (~29 µs each) show up
    in a profile.
- **Big-file signing** is bound by sigil's SHA-512 (~18 MB/s: a 14 GB checkpoint
  takes ~25 min to sign, ~13 to verify). That's sigil's to fix, and tula
  benefits with no change. It is filed with sigil:
  `2026-11-09-anukulana-sha512-throughput-bounds-big-file-signing.md`, with
  numbers from the same machine.

## 1.x.x — later / research (unscheduled)

- **mmap and concurrent writers** (audit D-7): a mapping is live, so a process
  that truncates or rewrites the file after validation changes what was checked
  (documented). Research a protected open without losing zero-copy for the
  common case: a Linux read lease (`F_SETLEASE`), or copy-on-open into an
  anonymous mapping.
- **Sharded checkpoints**: decide the scope first (ADR). A 70B+ model ships as
  many files plus an index (safetensors' `model.safetensors.index.json`). Either
  that is a codec convention (a signed shard manifest naming each file and its
  digest), or it belongs to the control-plane store (ADR 0001's line).
- **Size caps**: `TULA_READ_MAX_BYTES` is 1 TiB. STABILITY allows raising it in a
  MINOR, so do that when a real model needs it (≈ 500B parameters in BF16).
- **Binary size** (audit D-12): ~488 KB of the smoke binary is bayan's Unicode
  tables, arriving through sigil's bundle. Track sigil's issue
  `2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md`.
- **Locked deps**: under git-first resolution `cyrius.lock` is reproducible, so it
  could be committed and CI could run `cyrius deps --locked`. A maintainer call
  (it's gitignored today).

## v2 — potential items

A format v2 (`TULA_VERSION = 2`) is one coordinated, announced bump for every
consumer (STABILITY.md), and only for what 1.x can't carry. v2 readers keep
reading v1. Candidates, each to be argued in an ADR before it's planned:

- **Per-tensor digests under the signature**: sign the header, manifest and a
  table of per-tensor hashes instead of the whole payload. A reader then verifies
  only the tensors it touches (lazy, mmap-friendly), and signing stops costing two
  full passes through the hash. That is the structural fix for big-file signing;
  1.9.x's sigil speedup is the incremental one.
- **Variable-length names in the manifest**, retiring the names table, but only
  if ADR 0004's table proves insufficient in practice.
- **Richer entries**: more than 8 dims, and per-tensor attributes (quantization
  scheme, block size, scale dtype) as fields instead of naming conventions
  (ADR 0002 sidecars).
- **Configurable payload alignment** (e.g. 64 B or 4 KiB, recorded in the
  header) for SIMD loads and direct-to-device / `O_DIRECT` reads. v1 aligns to 8.
- **A sorted manifest as an invariant**, so lookup is O(log n) with no index to
  build (ADR 0007 considered it and rejected it for v1).
- **First-class structures for today's conventions**: the names table, the
  metadata table (1.6) and scale sidecars become format fields rather than
  reserved tensors.

---

## Gates / relations

- **CPU-only, no GPU.** `sigil` is the one external (sovereign) dep.
- **Consumers:** `rupantara` / `anukūlana` (Type-3 pretrained-import), the murti
  load-seam, the control-plane checkpoint store — all pull `dist/tula.cyr` via
  `[deps.tula]`. Keep the format stable for them; v2 is a coordinated event.
- **Cross-repo asks:**
  - anukulana — migrate, so its `gpt2-tula` demo becomes the real-weights gate
    (1.6.x).
  - sigil — SHA-512 throughput (filed with sigil, see 1.9.x), and the bayan
    binary-size issue (1.x.x).
- **Ecosystem context:** the AGNOS planning docs `type3-weight-import.md`
  (gap #1) + `software-port-path.md` (Tier A). tula is gap #1's format codec.
