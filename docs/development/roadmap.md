# tula — Roadmap (1.x)

> **For a secondary agent picking this up cold.** Read this + `CLAUDE.md`
> (conventions) + `docs/adr/0001-tula-scope.md` (scope) + `STABILITY.md` (what a
> 1.x release may change). tula is the sovereign weight-file **codec** — not a
> store, not the importer, not a tensor lib (ADR 0001). The public surface and
> on-disk format v1 are **frozen** (ADR 0003): every 1.x MINOR below is
> **additive only** (new functions, new `TULA_ERR_*` / `TULA_DT_*` values); a
> layout change is a 2.0. Item IDs `D-n` refer to the deferred list in
> [`docs/audit/2026-11-04-audit.md`](../audit/2026-11-04-audit.md) §5.

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
  `make dist` regenerated & committed (CI dist-sync gate) · CHANGELOG
  `[Unreleased]` updated. A speed change also gets a differential test against
  the old code and before/after `make bench` numbers in `docs/benchmarks.md`.
- **Do NOT** bump `VERSION` or `git` anything unless the maintainer asks — the
  maintainer cuts releases (bump VERSION → rename CHANGELOG `[Unreleased]` →
  `[x.y.z]` → tag). New work accretes under `[Unreleased]`.
- **`sigil` dep:** every build resolves git+tag, local and CI alike; the sigil tag
  must exist on GitHub. `path = "../sigil"` is read only in local mode
  (`CYRIUS_LOCAL=1` / `--local`), to build against a sigil working tree.

## Format invariants (don't break casually)

On-disk layout (all fields i64-aligned LE). Consumers depend on it; a change =
a format-version bump (`TULA_VERSION`) + reader back-compat consideration.

- **Header (64B):** `+0` magic `+8` version `+16` count `+24` manifest_off(=64)
  `+32` payload_off `+40` payload_len `+48` sig_off(0=unsigned) `+56` sig_len.
- **Entry (144B):** `+0` name[48] `+48` dtype `+56` ndim `+64` shape[8] `+128`
  data_off `+136` data_len.
- **Signature:** Ed25519 over content `[0..sig_off)`, appended at `sig_off`.

---

## Shipped

- **1.0.0** (2026-07-01) — M0 format + round-trip · M0b Ed25519 signed header via
  sigil · M1 file I/O (heap + mmap) · M2 dtype helpers (ternary / int8 / NF4;
  scales as `.scale` sidecars, ADR 0002) · M3 reader hardening (`tula_validate`,
  resource caps) · M4 fuzz + bench · M5 security audit + `SECURITY.md`. API +
  format v1 frozen (ADR 0003).
- **1.0.1 – 1.1.1** — toolchain realigns (cyrius 6.3.27 → 6.7.18, sigil 3.9.9 →
  3.13.15), no API change. 1.1.0 moved to git-first dependency resolution
  (cyrius ≥ 6.7.6: `path` is a local-mode override only).
- **1.1.2** (2026-11-04) — **P(-1)** hardening / optimization / repair
  ([audit](../audit/2026-11-04-audit.md)). Ten reproduced defects fixed: the file
  readers check the header's length against the real file (a truncated file
  crashed `tula_open_mmap` with SIGBUS); rejected mmaps unmap; the builder
  refuses arguments that corrupted or broke its output. Hot paths are 1.2–11.6×
  faster with byte-identical output. Fuzzing now runs against a guard page.
  105 → 178 assertions.
- **1.2.0** (2026-11-04) — **real checkpoints, checked**, all additive:
  `tula_builder_new_cap` (D-2: past 256 tensors); `tula_builder_add_checked`
  (D-1 short term: refuses long and duplicate names, O(1) per add through a name
  index); `tula_validate_strict` (D-4, new `src/check.cyr`: accepts only canonical
  buffers, duplicates found by a worst-case O(n log n) sort); `tula_verify_required`
  (D-5); `tula_find_scale` (D-6, the planned `quant_pair_ok`, returning the sidecar
  entry); `tula_entry_nelems` (D-11); error codes 13–16. The builder now copies
  names and shapes at add time. The fuzz PRNG's low bits were fixed. Plain-builder
  output is byte-identical to 1.1.2's. 178 → 274 assertions.
- **1.3.0** (2026-11-04) — **real names, real dtypes**, no format bump:
  - Long names via the `__tula.names__` table and 47-byte keys (D-1, ADR 0004):
    `tula_builder_add_long`, `tula_find_name` (verifies the full name),
    `tula_entry_full_name`, `tula_has_long_names`, plus `TULA_ERR_NAMES` in
    strict. The LoRA `lora_A`/`lora_B` collision round-trips as two tensors.
  - `TULA_DT_F32/F16/BF16` with integer-arithmetic IEEE conversions (D-10, ADR
    0005), exhaustively tested for the 16-bit formats.
  - The builder's output is byte-identical to 1.2.0's. 274 → 388 assertions.
- **1.4.0** (2026-11-04) — **big files**, no format change (ADR 0006):
  - `tula_builder_write_file(_signed)` streams the builder's file to disk
    (payloads straight from caller buffers; signed by mapping what was written),
    replacing the target atomically.
  - `tula_write_file_atomic`, `tula_file_len`, `tula_read_file_into`.
  - A new CI gate, `make bigfile`: 2.42 GB streamed past the 2 GiB allocation
    cap.
  - In-memory output byte-identical to 1.3.0's. 388 → 422 assertions.
- **1.5.0** (2026-11-04) — **lookup at scale**, no format change (ADR 0007):
  - The name index (`tula_index_new` / `_find` / `_find_scale` / `_free`): a
    sorted array, O(log n) lookups that crafted names can't degrade, with
    answers identical to `tula_find_name`.
  - A new CI gate, `make realmodels`: five real checkpoint inventories (GPT-2,
    Llama-2-7B, Mixtral-8x7B, a LoRA adapter, a QLoRA NF4 import) end to end.
  - Output and lookups identical to 1.4.0's. 422 → 435 assertions.

---

## 1.2.x — real checkpoints, checked (additive API)

**Goal:** a consumer can write a real model's tensor set, and reject anything
inconsistent with one call each. 1.2.0 shipped it (above). Left in the line:

- **1.2.x patches** — fixes found as consumers adopt the 1.2.0 calls; no new
  surface.
- **Consumer migration** (cross-repo, not tula code): anukulana and ifran move to
  `tula_builder_add_checked` / `tula_builder_new_cap` on the write side and
  `tula_validate_strict` → `tula_verify_required` → `tula_find_scale` on the
  read side, as `examples/consumer.cyr` does.

## 1.3.x — real names, real dtypes

**Goal:** tula stores what HF/LoRA checkpoints actually contain, without a
format bump. 1.3.0 shipped both halves (above). The old plan split them, with the
dtypes as "1.3.x", but new `TULA_DT_*` values are MINOR-only (STABILITY.md), so
they landed in 1.3.0 together. Left in the line:

- **1.3.x patches** — fixes as consumers adopt long names and the new dtypes; no
  new surface.
- **Consumer migration** (cross-repo): anukulana writes HF/LoRA names through
  `tula_builder_add_long` and reads with `tula_find_name`. It keeps BF16/F16
  source tensors in their dtype rather than widening them to f64.
- **Later dtype candidates** need their own ADR before a MINOR:
  - FP8 (E4M3 / E5M2), which come in several incompatible NaN/inf conventions.
  - int4 blockwise (GGUF-style Q4).

## 1.4.x — big files

**Goal:** multi-GB checkpoints on both sides of the codec. 1.4.0 shipped all four
planned pieces (above). The signed stream needed **no** sigil change: the writer
signs a read-only mapping of the file it just wrote. Left in the line:

- **1.4.x patches** — fixes as consumers stream real checkpoints; no new surface.
- **Signing speed is sigil's** (cross-repo): its SHA-512 runs at ~18 MB/s, so
  Ed25519 over a 14 GB checkpoint takes ~25 min to sign and ~13 to verify. File
  the throughput issue with sigil, with the numbers in `docs/benchmarks.md`. tula
  needs no change to benefit.
- **Consumer migration** (cross-repo): anukulana writes real checkpoints through
  `tula_builder_write_file_signed` and loads them with `tula_open_mmap`.

## 1.5.x — lookup at scale, and a real round-trip

**Goal:** large checkpoints are cheap to resolve by name, and real model
inventories go through the whole codec. 1.5.0 shipped the index and the
inventory gate (above). Left in the line:

- **1.5.x patches** — fixes as importers adopt the index; no new surface.
- **The real-weights round trip is anukulana's** (cross-repo). Its `gpt2-tula`
  demo already imports the real GPT-2 safetensors, NF4-quantizes it, saves a
  signed tula checkpoint, reloads it and checks the result bit for bit. It
  runs on tula 1.0.1 and cyrius 6.6.2 (its manifest, read 2026-11-04), and needs
  the checkpoint staged. Moving anukulana to the current toolchain and tula,
  then running that demo in its own CI over `tula_builder_write_file_signed`,
  `tula_open_mmap` and the index, is the real-weights gate. tula's CI can't run
  it without depending on its own consumer.

## 1.x — later / research

- **mmap and concurrent writers** (D-7): the mapping is live, and the caveat is
  documented. Research a protected open (a Linux read lease via `F_SETLEASE`,
  or copy-on-open into an anonymous mapping) without losing zero-copy for the
  common case.
- **Throughput**: vectorized dequant (cyrius has `f64v` dot builtins); parallel
  unpack over cyrius threads for multi-GB tensors.
- **Cross-target CI**: run the file-reader tests on aarch64 and macOS (lseek,
  mmap, SIGBUS behaviour), not only x86_64 Linux.
- **Binary size** (D-12): ~488 KB of the smoke binary's data is bayan's Unicode
  tables, arriving via sigil's bundle. Track sigil's open issue
  `2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md`.
- **Locked deps**: under git-first resolution `cyrius.lock` is reproducible, so it
  could be committed and CI could run `cyrius deps --locked`. A maintainer call
  (it's gitignored today).

## 2.0 — only if 1.x can't carry it

A format v2 (`TULA_VERSION = 2`, readers keep v1) only if the 1.3 long-name
sidecar proves insufficient, or a need appears that v1's fixed 144-byte entry
cannot express (e.g. > 8 dims, per-tensor metadata). Planned and announced,
never incidental (STABILITY.md).

---

## Gates / relations

- **CPU-only, no GPU.** `sigil` is the one external (sovereign) dep.
- **Consumers:** `rupantara` / `anukūlana` (Type-3 pretrained-import), the murti
  load-seam, the control-plane checkpoint store — all pull `dist/tula.cyr` via
  `[deps.tula]`. Keep the format stable for them; a format bump is a coordinated
  event. 1.2.0's checked add and strict validator are what anukulana should
  switch to first (see 1.2.x).
- **Cross-repo asks:** sigil — SHA-512 throughput (~18 MB/s bounds big-file
  signing; see 1.4.x) and the bayan binary-size issue. The multi-part Ed25519
  sign once planned here isn't needed (ADR 0006).
- **Ecosystem context:** the AGNOS planning docs `type3-weight-import.md`
  (gap #1) + `software-port-path.md` (Tier A). tula is gap #1's format codec.
