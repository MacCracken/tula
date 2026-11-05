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

---

## 1.2.x — real checkpoints, checked (additive API)

**Goal:** a consumer can write a real model's tensor set, and reject anything
inconsistent with one call each. Blocks: anukulana's Type-3 import of real
checkpoints.

- **1.2.0**
  - **Sized builder** (D-2): `tula_builder_new_cap(max)`. `TULA_BUILDER_MAX` (256)
    stays the frozen default for `tula_builder_new`. Real checkpoints exceed it
    (Llama-2-7B: 291 tensors; Mixtral-8x7B: ~995). The builder layout is private,
    so it can carry its own cap.
  - **Checked add** (D-1, short term): `tula_builder_add_checked(...)` refuses a
    name over 47 chars (`TULA_ERR_NAME_LONG`) and a name already in the builder
    (new `TULA_ERR_DUP_NAME`) instead of truncating into a collision. The plain
    add keeps its frozen truncating behaviour.
  - **Strict validator** (D-4): `tula_validate_strict(buf, len)` = `tula_validate`
    plus no overlapping tensors, unique names, 8-byte-aligned `data_off`, zero
    unused dims, and `data_len == tula_packed_len(dtype, nelems)` for known
    dtypes. New `TULA_ERR_*` codes, e.g. `OVERLAP` and `SHAPE`. This matches what
    careful safetensors readers enforce (audit §4). Fuzz invariant: strict-accepted
    ⊂ accepted, and checked-builder output is always strict-valid.
  - **Signature required** (D-5): `tula_verify_required(r, pk)` → `TULA_OK` /
    `TULA_ERR_UNSIGNED` / `TULA_ERR_SIG`, so rejecting a stripped signature is one
    call.
  - **Quant pair check** (D-6): `tula_quant_pair_ok(r, e, block)` — the
    `"<name>.scale"` sidecar exists, is f64, passes `payload_ok`, and has at least
    the scales the unpack will read (per-tensor, per-row or per-block).
  - **Element count** (D-11): `tula_entry_nelems(e)` → count, or −1 for a negative
    or overflowing shape, so consumers stop re-deriving it.
  - Docs: `docs/api.md` section per helper; `examples/consumer.cyr` switched to the
    strict validator + `verify_required` + `quant_pair_ok`.
- **1.2.x patches** — fixes found while landing the above; no new surface.

## 1.3.x — real names, real dtypes

**Goal:** tula stores what HF/LoRA checkpoints actually contain, without a
format bump.

- **1.3.0 — long names** (D-1, proper). **ADR 0004 first.** The likely shape,
  following ADR 0002's sidecar precedent: a reserved tensor (e.g.
  `"__tula.names__"`) holds the full names, and each entry's 48-byte field holds
  a deterministic short key. A 1.x reader that knows nothing of it still opens
  the file; `tula_find_name(r, long_name)` resolves through the table. The LoRA
  `lora_A` / `lora_B` collision (audit §5) is the acceptance test.
- **1.3.x — F32 / F16 / BF16** (D-10): new `TULA_DT_F32` / `TULA_DT_F16` /
  `TULA_DT_BF16`. `tula_packed_len` / `payload_ok` learn their sizes, plus
  conversion helpers to/from f64 (round-to-nearest-even, NaN/Inf/subnormal
  exact), each with a differential test. Most real checkpoints ship BF16 or F16.

## 1.4.x — big files

**Goal:** multi-GB checkpoints on both sides of the codec.

- **1.4.0 — streaming writer** (D-3): `tula_builder_write_file(b, path)` writes the
  header and manifest, then each tensor straight from the caller's memory to the
  fd, with no whole-file allocation. Today `tula_serialize` needs one allocation
  of the whole file, and the stdlib caps one at 2 GiB.
- **1.4.x — signed streaming write**: v1 signs `[0, sig_off)` as one Ed25519
  message, and a stream can't be signed in one piece. This needs a multi-part
  `ed25519_sign` from sigil. **File the request with sigil**; the on-disk
  signature stays identical.
- **Atomic write** (D-8): `tula_write_file_atomic` (temp file + fsync + rename, via
  the stdlib's `file_write_atomic`), so a crash never leaves a half file under
  the final name.
- **Caller-buffer read** (D-9): `tula_read_file_into(path, buf, cap)`, so a file
  that fails validation doesn't strand a heap buffer the bump allocator can't
  free. It also lets the heap path read files over 2 GiB.

## 1.5.x — lookup at scale, and a real round-trip

- **Name index**: `tula_index_new(r)` → O(1) `tula_index_find`. `tula_find` is a
  linear scan (~3 ns/entry since 1.1.2), so looking up every tensor of a
  thousands-of-tensors checkpoint is O(n²).
- **Real checkpoint round-trip**: import a real (small) checkpoint through
  anukulana → tula file → load, in CI, using 1.2–1.4. This replaces the old
  "attn11 checkpoint" placeholder.

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
  switch to first.
- **Cross-repo asks:** sigil — multi-part Ed25519 sign (1.4.x) and the bayan
  binary-size issue.
- **Ecosystem context:** the AGNOS planning docs `type3-weight-import.md`
  (gap #1) + `software-port-path.md` (Tier A). tula is gap #1's format codec.
