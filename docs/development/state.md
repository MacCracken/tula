# tula — Current State

> **Last refresh**: 2026-11-12 | **Cadence**: every release.
> `CLAUDE.md` is preferences / process (durable); this file is **state**
> (volatile) — version, sizes, counts.

## Version

**1.0.0 — API frozen 2026-07-01** (M0–M5; format **v1**). Prior cut: 0.1.0 (M0 +
M0b: format + round-trip + Ed25519 signed header). **v1.0 added M1–M5.** M1 —
file I/O: `tula_write_file`
/ `tula_read_file` (heap) / `tula_open_mmap` (zero-copy) / `tula_close_mmap`; tula
files are self-describing so reads need no `stat()`. M2 — dtype payload helpers
(`src/dtype.cyr`): ternary/int8/NF4 pure pack/unpack; scales stored as sidecar
`"<name>.scale"` tensors (ADR 0002 — **no format-version bump**, the 144B entry
stays frozen). M3 — reader hardening (`tula_validate` + a strict `tula_open`):
untrusted/lying/truncated input rejected with a specific `TULA_ERR_*`, overflow-
safe, resource-capped (2²⁰ tensors / 2⁴⁰ bytes), file readers bomb-guarded before
alloc/mmap. M4 — `programs/fuzz.cyr` (2M+ iters clean, validates M3) +
`programs/bench.cyr` + `docs/benchmarks.md`. M5 — 6-dimension security audit
(`docs/audit/2026-07-01-audit.md`, verdict PASS) + `SECURITY.md`; closed a
consumer-side over-read with `tula_entry_payload_ok`. **105 assertions** across 5
suites (`roundtrip.tcyr` 22 + `sign.tcyr` 8 + `fileio.tcyr` 16 + `dtype.tcyr` 29 +
`hardening.tcyr` 30), all green; builds + tests warning-clean.

VERSION is **1.11.0** (`tula_version_int()` returns `11100`). 1.0.1–1.1.1 are
toolchain/dep realigns. **1.1.2 is the P(-1) pass**
([audit](../audit/2026-11-04-audit.md)): ten reproduced defects fixed (worst: a
truncated file crashed `tula_open_mmap` with SIGBUS), hot paths 1.2–11.6× faster
with byte-identical output, and no API or format change. **1.2.0 — real
checkpoints, checked** (additive): the sized builder, the checked add, the strict
validator (`src/check.cyr`), `tula_verify_required`, `tula_find_scale`,
`tula_entry_nelems`, error codes 13–16. **1.3.0 — real names, real dtypes**: long
names through the `__tula.names__` table and 47-byte keys (ADR 0004;
`src/names.cyr`), and `TULA_DT_F32/F16/BF16` with integer-arithmetic IEEE
conversions (ADR 0005). Still no format bump. **1.4.0 — big files** (ADR 0006):
`tula_builder_write_file(_signed)` streams past the 2 GiB allocation cap and
replaces the target atomically; `tula_write_file_atomic`, `tula_file_len` and
`tula_read_file_into` round it out. **1.5.0 — lookup at scale** (ADR 0007): the
name index (`src/index.cyr`), sorted so crafted names can't degrade it, and the
`make realmodels` gate over five real checkpoint inventories. **1.6.0 — file
metadata** (ADR 0008): sorted key/value text pairs in the `__tula.meta__` table
(`src/meta.cyr`), signed with the tensors, and readable by every 1.x reader.
**1.6.1** (patch): on Linux the streaming writers build the file in a nameless
`O_TMPFILE` inode and name it only once it is signed, closing ADR 0006's
write-to-sign window (the named `O_EXCL` temp is the fallback); fuzz phase H
checks the writers against `finish`; CI gains native aarch64 Linux and macOS
runners. **1.6.2** (patch): the macOS leg is a hard gate, and `tula_write_file` /
`tula_write_file_atomic` write through tula's own loop (at most 1 GiB per
request), so buffers over INT_MAX bytes work on macOS too.
**1.7.0 — integer and boolean dtypes** (ADR 0009):
`TULA_DT_I16/I32/I64/U8/BOOL` = codes 7–11, stored raw; strict rejects a BOOL
byte other than 0 or 1 with `TULA_ERR_VALUE` (19). 1.6.2 reads such files (open,
verify, names, metadata); its strict says `TULA_ERR_DTYPE`.
**1.8.0 — compact formats**: OCP FP8 `TULA_DT_F8_E4M3` / `F8_E5M2` = codes 12–13 (ADR 0010),
exact non-saturating conversions in integer arithmetic; `TULA_DT_INT4` = 14
(ADR 0011), signed codes with an f64 `.scale` sidecar, quantized by Q4_0's rule,
strict-checked for an odd count's unused nibble. 1.7.0 reads such files; its
strict says `TULA_ERR_DTYPE`.
**1.9.0 — throughput**: the array helpers are 1.4–6.7× faster on one thread with the same
output (tables for the byte and nibble formats, one loop per float format), and
`tula_unpack_par` (ADR 0012, `src/par.cyr`) splits an unpack across threads.
Strict, adds and short-name lookups cost 12–35% less per call. A cross-version
diff against the 1.8.0 tag matched every changed call's output.
**1.9.1** (patch): faster kernels. NF4 pack finds each code through 15 exact thresholds instead of
scanning the codebook, and the F16 / BF16 unpacks read a per-call table from
262,144 elements. Every output matches 1.9.0 (cross-version diff).
**1.10.0 — a protected open** (ADR 0013, audit D-7). `tula_open_protected` maps an fs-verity
file zero-copy and reads any other file into a private copy, so no later
rewrite or truncation reaches the validated reader.
**1.11.0 — sharded checkpoints** (ADR 0014). A shard set is ordinary tula files plus a
signed, tensor-less manifest whose `tula.shards` key lists each shard's
SHA-256, size and name. `tula_builder_set_shards` writes one; `tula_set_open`
verifies one (one signature, then the shards' SHA-256 in parallel, ~1.2 GB/s at
8 threads) and `tula_set_find` resolves names across it. `TULA_ERR_SHARDS` = 20.
Post-1.0 work
accretes under a fresh CHANGELOG `[Unreleased]` and is additive-only (SemVer);
the maintainer bumps VERSION + renames the section + tags at each subsequent cut.

## Tests, fuzz, gates (1.11.0)

**923 assertions** across 18 suites, all green: `meta.tcyr` 98, `shards.tcyr` 87
(1.11.0: a written and opened set, every refusal with its code and shard, the
builder's and strict's rules), `fp8.tcyr` 81,
`names.tcyr` 77, `stream.tcyr` 68, `builder.tcyr` 67, `strict.tcyr` 67,
`ints.tcyr` 61, `dtype.tcyr` 50, `int4.tcyr` 48, `kernels.tcyr` 44 (the table
and inline paths, `tula_unpack_par` against the serial helpers, and 1.9.1's
16-bit tables and NF4 thresholds), `floats.tcyr` 37, `protected.tcyr` 35
(1.10.0: the copy branch under an in-place rewrite and a truncation, the forced
zero-copy branch, the verity check), `fileio.tcyr` 30,
`hardening.tcyr` 30,
`roundtrip.tcyr` 22, `index.tcyr` 13, `sign.tcyr` 8.
- **Targets**: x86_64 Linux natively; aarch64 Linux under qemu (every suite, the
  consumer, realmodels, bigfile and the fuzzer). CI's `cross-target` job runs the
  same on native `ubuntu-26.04-arm` and `macos-15` (arm64), both hard gates
  (macOS since 1.6.2, after 1.6.1's run on `macos-14` went green end to end;
  GitHub retired that image on 2026-11-02). x86_64 macOS isn't covered.
- `make realmodels` (CI): GPT-2, Llama-2-7B, Mixtral-8x7B, a LoRA adapter, a
  QLoRA NF4 import, (1.7.0) a GPTQ 4-bit Llama-2-7B (I32 `qweight` / `qzeros` /
  `g_idx`, F16 `scales`; 963 tensors), and (1.8.0) Llama-2-7B as an FP8 E4M3
  import (291) and as a Q4_0-style INT4 import with `.scale` sidecars (517), with
  real names, ranks, counts and dtypes, dims ÷ 64. Each is written signed, read, strict-validated,
  verified and resolved by index. (1.11.0) Llama-2-70B, BF16, 723 tensors, as a
  shard set: 15 unsigned shards and a signed manifest, opened with
  `tula_set_open` and resolved through `tula_set_find`.
- `make bigfile` (CI): a 2.36 GB file, one tensor over INT_MAX bytes, streamed,
  mapped, strict-validated, read into a caller buffer, and (1.6.2) written back
  out from it by `tula_write_file_atomic` and `tula_write_file`, each copy
  compared word for word, then (1.10.0) opened protected: a private copy past
  the 2 GiB cap, strict-validated.
- `make verity` (CI, 1.10.0): the protected open's zero-copy branch on a real
  fs-verity file, in an ext4 image made with `-O verity` and loop-mounted at
  `build/verity`. It checks the flag, that the kernel refuses a rewrite, and
  that the reader is a mapping of the file. Elsewhere (this machine's ext4 has
  no verity feature, and setting one needs root) it prints SKIP.
- `make bigfile-signed` (local; minutes, bound by sigil's ~18 MB/s SHA-512): the
  same, signed and verified.
- `floats` checks F16/BF16 exhaustively (every code, every midpoint) and F32
  against the hardware; `fp8` does the same for E4M3/E5M2 (every code, every
  midpoint, overflow and underflow edges, 40,000 values against a brute-force
  oracle). Outside the repo an exact-rational reference agreed on all 512 FP8
  decodes and 400,000 encodes.
- `dtype` and `builder` include differential tests against the 1.1.1
  implementations.
- `make fuzz` (CI, ~65 s): 3,204,500 iterations with every buffer ending at a
  `PROT_NONE` guard page, 0 faults. It covers:
  - a payload-guard + unpack phase (4.60M entries, all fifteen dtypes, each
    data_len held to the fuzzer's own size table);
  - a strict phase, where 92,821 strict accepts were all confirmed by brute
    force, including the find-name round trip, every BOOL byte 0/1, an odd
    INT4's last high nibble and the size table; 12,821 `TULA_ERR_VALUE`
    rejections;
  - phase F, which mutates a names table, and phase G, a metadata table;
  - phase H (1.6.1): 1,500 random builders through the streaming writers (737
    nameless, the rest on the named temp), every file byte-identical to
    `finish`, 446 canonical ones strict-accepted, no temp left behind;
  - phase I (1.7.0; 1.8.0 adds FP8 and INT4): 300,000 mutations of a file
    holding the integer, boolean, FP8 and INT4 dtypes, aimed at payload
    bytes, dtype fields and shapes;
  - phase J (1.9.0): 400 parallel unpacks (nine dtypes, up to five chunks,
    odd blocks, 1–9 threads) against the serial helpers, payload and scales
    each ending at a guard page;
  - phase K (1.11.0): 200,000 mutations of a manifest's shard list, strict's
    verdict matched against the fuzzer's own reading (18,921 accepted, 114,006
    refused), and 300 sets on disk with one shard corrupted or cut, every one
    refused by `tula_set_open`.

  `fmt` / `lint` / `vet` / `deny` clean; `cyrius doc --check src/*.cyr`:
  0 undocumented.

## Toolchain

Cyrius pin **6.7.18** (`cyrius.cyml`). Deps: the sigil-consumer stdlib set +
**sigil 3.13.15** (Ed25519), sigil's latest release and the copy 6.7.18 bundles. Every build resolves
`[deps.sigil]` **git+tag**, local and CI alike (cyrius ≥ 6.7.6, git first). The sigil
tag must exist on GitHub for CI + the release to pass.

**Local sigil work:** `CYRIUS_LOCAL=1` (or `--local`) builds the `../sigil` working
tree under `build/local-deps/`; `lib/` and `cyrius.lock` stay the tag's. Without the
switch a build prints one `hint:` line naming the unused checkout.

**Pin history:** 6.3.27 → 6.5.27 (2026-08-17) → 6.6.2 (2026-09-11) → 6.6.20
(2026-11-04, 1.0.3) → 6.7.9 (2026-11-04, 1.1.0) → **6.7.18** (2026-11-04, 1.1.1).
Since 6.6.18, `cyrius distlib` writes a sidecar only for leaves the bundle itself needs.
tula needs none beyond what sigil's sidecar brings, so there is no `dist/tula.deps`.

**Smoke binary: 603,872 B** (1.9.0: +8 KB for the parallel unpack and the stdlib thread code it now reaches; ~488 KB is data). Most of the data is bayan's
`lib/unicode/` tables, which sigil's bundle pulls in. DCE can't drop global initializers,
and tula itself makes no bayan calls. It shrinks when sigil's open issue
`2026-11-01-sigil-mldsa-pulls-bayans-unicode-tables.md` lands.

## Build artifacts

- `programs/smoke.cyr` → `build/tula_smoke` (link-check).
- `programs/fuzz.cyr` → `build/tula_fuzz` (`make fuzz`) + `programs/bench.cyr` →
  `build/tula_bench` (`make bench`; writes `build/tula_bench.tula`) +
  `examples/consumer.cyr` → `build/tula_consumer` (`make example`, a CI gate).
  Tests and the example write their files under `build/`.
- `dist/tula.cyr` — the distlib bundle consumers pull via `[deps.tula]`
  (regenerate with `make dist`; leaves `ed25519_*` unresolved — consumer supplies
  sigil, the standard consumer-bundle pattern). `cyrius.lock` is gitignored (CI
  re-resolves fresh).
- CI (`.github/workflows/ci.yml`) + release (`.github/workflows/release.yml`).

## Next

Next: on CI, confirm the fs-verity step runs rather than skips, and read the
native arm64 runner's `make realmodels` time for the sharded 70B set (sigil's
SHA-256 has no SHA-NI path there); 1.11.x patches only for fixes. The open lines are in the [roadmap](roadmap.md): 1.12.x
the remaining dtypes, 1.13.x throughput follow-ups, 1.14.x zero-copy
protection for unsealed files, then 1.x.x (shard-set follow-ups among them) and
the v2 candidates. Each waits on
its gate (an importer's need or a decision). Cross-repo: anukulana's migration
(the real-weights gate) and sigil's SHA-512 throughput.
