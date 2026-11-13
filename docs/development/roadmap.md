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
  `cross-target` runners) · `make verity` PASS or SKIP (CI's build job runs it
  on an fs-verity image) · `make dist` regenerated &
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
    order, unused-nibble rule and quantization rule (ADR 0011);
  - shard sets: a tensor-less manifest whose `tula.shards` key lists each
    shard's SHA-256, size and name (ADR 0014).

  A new convention (a reserved tensor, a naming rule) is a MINOR with its own
  ADR, and must stay readable by every older 1.x reader.

---

## How the lines below are ordered

Shipped lines (through 1.11.0) aren't listed; a released line takes patches
only: fixes, with no new function, dtype or convention. The lines below are
ordered by how soon a consumer is likely to need them. Each starts when its gate
is met (an importer's need, a decision), not on a date, and new dtype codes start
at 15.

## 1.12.x — the remaining dtypes

**Goal:** the formats ADRs 0009–0011 left out, each when an importer needs it.

- **Asymmetric 4-bit** (Q4_1, AWQ/GPTQ with zero points): an unsigned 4-bit
  dtype and a `.min` / zero-point sidecar convention beside `.scale` (ADR 0011).
  GPTQ/AWQ already import losslessly as `I32`.
- **FP8 variants** (ADR 0010): saturating conversions (as their own helpers;
  the non-saturating ones are frozen) and the FNUZ variants (`E4M3FNUZ`,
  `E5M2FNUZ`, with their own bias and a single NaN).
- **Unsigned 16/32/64-bit integers and element-read helpers** (ADR 0009).

## 1.13.x — throughput follow-ups

**Goal:** what ADR 0012 deferred, when a consumer's profile asks for it.

- **A parallel pack.** INT8's per-tensor absmax needs a reduction across
  threads; the blockwise and float packs split as the unpacks do.
- **A caller-owned worker pool**, if per-call thread starts (~29 µs each) show
  up beside `tula_unpack_par`.

## 1.14.x — zero-copy protection for unsealed files

**Goal:** `tula_open_protected` without the copy on filesystems that can
snapshot. Today it maps fs-verity files and copies anything else (ADR 0013).

- **A reflink snapshot**: `FICLONE` into a nameless file in the same directory
  on btrfs/XFS, and `clonefile` on APFS, mapped and validated like the verity
  case. Do it when a consumer's files live there and CI can test it. Neither
  this machine nor CI has such a filesystem today.

## 1.x.x — later / unscheduled

- **Shard-set follow-ups** (ADR 0014), when an importer or loader asks:
  - splitting one builder into shards (`tula_builder_write_sharded`, by a byte
    budget);
  - opening part of a set, verifying only the shards a loader reads (a
    pipeline-parallel rank's layers).

  1.11.0's `tula_set_open` checks the whole set.

- **Size caps**: `TULA_READ_MAX_BYTES` is 1 TiB. STABILITY allows raising it in a
  MINOR, so do that when a real model needs it (≈ 500B parameters in BF16).
- **Binary size** (audit D-12): ~488 KB of the smoke binary is bayan's Unicode
  tables, arriving through sigil's bundle. Track sigil's issue
  `2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md`.
- **Locked deps**: under git-first resolution `cyrius.lock` is reproducible, so it
  could be committed and CI could run `cyrius deps --locked`. A maintainer call
  (it's gitignored today).
- **An x86_64 macOS CI leg**, once GitHub's hosted Intel runners are practical.
  The aarch64 Linux and arm64 macOS legs are hard gates.

## v2 — potential items

A format v2 (`TULA_VERSION = 2`) is one coordinated, announced bump for every
consumer (STABILITY.md), and only for what 1.x can't carry. v2 readers keep
reading v1. Candidates, each to be argued in an ADR before it's planned:

- **Per-tensor digests under the signature**: sign the header, manifest and a
  table of per-tensor hashes instead of the whole payload. A reader then verifies
  only the tensors it touches (lazy, mmap-friendly), and signing stops costing two
  full passes through the hash. That is the structural fix for big-file signing;
  a faster SHA-512 in sigil is the incremental one.
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
- **Cross-repo asks** (not tula code):
  - **anukulana's migration**, which makes its `gpt2-tula` demo the
    real-weights gate. That demo imports the real GPT-2 checkpoint,
    NF4-quantizes it, saves a signed tula file, reloads it and checks the result
    bit for bit. It needs anukulana on the current toolchain and tula, and the
    checkpoint staged in its CI. tula's own CI can't run it without depending on
    its consumer, so `make realmodels` covers tula's side.
  - **Other consumers** move onto the newer calls (checked and long adds, strict
    reads, streaming writes, the index, metadata, `tula_unpack_par`,
    `tula_open_protected`), as `examples/consumer.cyr` shows.
  - **sigil's SHA-512 throughput** bounds big-file signing (~18 MB/s: a 14 GB
    checkpoint takes ~25 min to sign, ~13 to verify). tula benefits with no
    change. Filed with sigil:
    `2026-11-09-anukulana-sha512-throughput-bounds-big-file-signing.md`.
  - **sigil's bayan binary-size issue** (see 1.x.x).
- **Ecosystem context:** the AGNOS planning docs `type3-weight-import.md`
  (gap #1) + `software-port-path.md` (Tier A). tula is gap #1's format codec.
