# tula — Benchmarks

Harness: `programs/bench.cyr` (`make bench`). Numbers are **indicative**: they
depend on the machine, the filesystem and page-cache state. Re-run locally with
`make bench` for your own hardware.

## Method

- **File paths** on a large synthetic file: 200 f64 tensors × 512 KiB =
  104,886,464 bytes, each tensor seeded with a non-zero per-page pattern so the
  file is not sparse. The file is written to `build/` and read straight back, so
  reads are page-cache-warm.
- **In-memory paths a consumer pays on every load** (added in 1.1.2): serialize
  (builder → one buffer), `tula_validate` on the 200-entry buffer, `tula_find`
  over 256 realistic names (`model.layers.<i>.mlp.down_proj.weight`, a shared
  13-byte prefix; every name looked up, 20 sweeps), and the dtype helpers on 2²⁰
  elements.
- Each op runs `BN_ROUNDS` (5) rounds and reports the **minimum** (the
  least-noise estimate), in µs. Throughput is bytes or elements over that time.
- `mmap open` is the lazy map latency (nothing faulted in). `mmap scan` touches
  one byte per 4 KiB page to force fault-in.

## Results — 1.1.2 (P(-1) pass)

Machine: **AMD Ryzen 7 5800H** (16 threads), Linux, ext4. Cyrius **6.7.18**. The
1.1.1 column is the same widened harness run on the unchanged 1.1.1 code; the
two versions' outputs are byte-identical (see the
[audit](audit/2026-11-04-audit.md) §2).

| Op | 1.1.1 | 1.1.2 | Speedup |
|---|---:|---:|---:|
| serialize (100 MB) | 177 ms · 591 MB/s | 26 ms · 4,036 MB/s | 6.8× |
| write (100 MB) | 20–210 ms | 177–211 ms | disk-bound, noisy |
| read (heap, 100 MB) | 12.2 ms · 8.6 GB/s | 12.4–13.0 ms · 8.1–8.5 GB/s | — |
| mmap open | 10 µs | 10–11 µs | — |
| mmap scan | 0.2–0.3 ms | 0.2 ms | — |
| validate (200 entries) | 2.89 µs | 2.75–2.77 µs | — |
| `tula_find` (256 names) | 8,860 ns | 761–766 ns | 11.6× |
| NF4 pack (2²⁰) | 155 ms · 6.7 Melem/s | 40 ms · 26 Melem/s | 3.9× |
| NF4 unpack (2²⁰) | 12.5 ms · 83 Melem/s | 4.2–4.4 ms · 237–248 Melem/s | 3.0× |
| ternary unpack (2²⁰) | 6.7 ms · 155 Melem/s | 2.8 ms · 373–377 Melem/s | 2.4× |
| int8 dequant (2²⁰) | 3.0 ms · 350 Melem/s | 2.5 ms · 416–421 Melem/s | 1.2× |

Where the time went: serialize copied the payload with the stdlib `memcpy`, a
byte loop. `tula_find` called `streq`, which ran `strlen` on both strings for
every entry. NF4 pack scanned all 16 codebook entries through a compare chain
for every element. NF4 unpack resolved each code through that compare chain and
re-divided for each element's block. Ternary unpack made a function call, a
divide and a modulo per element. Each fix keeps the same arithmetic: the
results are bit-identical, only faster.

### Added in 1.2.0 (same machine and harness)

| Op | 1.2.0 | Notes |
|---|---:|---|
| `tula_validate_strict`, 200 tensors | 42 µs | ~15 µs of per-entry rules + ~28 µs duplicate sort; vs 2.8 µs for `tula_validate` |
| `tula_validate_strict`, 256 long names | 77 µs | names sharing a 13-byte prefix |
| `tula_builder_add` | 171 ns | per add, including the name-index insert |
| `tula_builder_add_checked` | 192 ns | per add, plus the length check and duplicate lookup |

The strict duplicate check sorts (name hash, entry) records with a heapsort: worst
case O(n log n) for any names, about 9 ns per comparison. Up to 512 tensors the
records live on the stack; beyond that in a private mapping, unmapped afterwards.
Measured on a 1,000-tensor file (realistic `model.layers.*` names, mapping path): **316 µs**.

### Added in 1.3.0

| Op | 1.3.0 | Notes |
|---|---:|---|
| `tula_f32_pack` (2²⁰) | 9.5 ms · 109 Melem/s | f64 → binary32, integer RNE |
| `tula_f32_unpack` (2²⁰) | 7.6 ms · 137 Melem/s | exact widening |
| `tula_f16_pack` / `tula_bf16_pack` (2²⁰) | 10.3–10.5 ms · 99–102 Melem/s | |
| `tula_f16_unpack` / `tula_bf16_unpack` (2²⁰) | 7.6 ms · 138 Melem/s | |
| `tula_builder_add_long` | 640–720 ns | per add of a 60-char LoRA name (key + copy) |
| `tula_find_name`, 256 long names | 2.1 µs | key hash + scan + table binary search + full-name check |
| `tula_builder_add_checked` | 213 ns | was 192 in 1.2.0: the long-name bookkeeping |

The array conversions take an inline fast path for normal numbers. A normal f64
whose result is a normal narrow value below the top exponent has its fraction
rounded and added to the exponent field, so a carry bumps the exponent the way
IEEE rounding does. Everything else goes through the general conversion. That's
about 2.2× the per-element scalar calls (46 → 102 Melem/s pack, 68 → 138 unpack)
and bit-identical (tested on every 16-bit code and midpoint, and 300k F32 cases).

### Added in 1.4.0

| Op | 1.4.0 | Notes |
|---|---:|---|
| `tula_builder_write_file`, 100 MB | 289 ms · 363 MB/s | streamed + fsync + rename; vs serialize (27 ms) + plain write (195 ms), which doesn't fsync |
| `make bigfile`: stream 2.42 GB | 5.6 s · ~430 MB/s | past the 2 GiB allocation cap; strict validate < 1 ms; mmap; spot checks |
| `tula_read_file_into`, 2.42 GB | 315 ms | page-cache warm, into a caller's anonymous mapping |
| `make bigfile-signed`: write + sign 2.42 GB | 266–274 s | two SHA-512 passes in `ed25519_sign` (two runs) |
| `tula_verify_required`, 2.42 GB | 127–129 s | one SHA-512 pass |
| sigil SHA-512 (measured directly) | ~18 MB/s | 64 MiB in 3.6 s; `ed25519_sign` 7.2 s, `ed25519_verify` 3.6 s |

### 1.6.1: nameless temp files

| Op | named temp | nameless (the Linux default) | Notes |
|---|---:|---:|---|
| `tula_builder_write_file`, 100 MB | 249 ms · 421 MB/s | 249 ms · 421 MB/s | three alternating runs each; the same work plus one `linkat` |
| `make bigfile` (1.6.0's shape): stream 2.42 GB | — | 5.7 s | 1.4.0 measured 5.6 s on the named path |
| `make bigfile` (1.6.1): stream 2.36 GB, one 2.2 GB tensor | — | 6.3 s | requests of at most 1 GiB; `tula_read_file_into` 377 ms |
| `make bigfile-signed` (1.6.1): write + sign 2.36 GB | — | 244 s | verify 121 s; still bound by sigil's SHA-512 |

### 1.6.2: whole-buffer writes on tula's own loop

`make bigfile`'s write-back step: the 2.36 GB buffer `tula_read_file_into` filled,
written out again. The same program was built against 1.6.1's `src/fileio.cyr`
(the stdlib's loops) and 1.6.2's, and run alternately, two runs each, on x86_64
Linux (where the stdlib's single request still works).

| Op, 2.36 GB | 1.6.1 (stdlib) | 1.6.2 (requests ≤ 1 GiB) | Notes |
|---|---:|---:|---|
| `tula_write_file_atomic` | 5.2–5.5 s | 5.4–5.7 s | temp, write, fsync, rename; 1.6.2 also fsyncs the directory |
| `tula_write_file`, over that copy | 5.3–5.5 s | 5.3 s | truncate and write, no fsync |

### 1.7.0: integer and boolean dtypes

The new dtypes are raw, so the only new cost is strict's BOOL rule (ADR 0009),
the first strict rule that reads tensor values. Measured with `make bench` on a
16 MiB tensor of the same bytes, stored as BOOL and as U8:

| Op | 1.7.0 | Notes |
|---|---:|---|
| `tula_validate_strict`, a 16 MiB BOOL tensor | 4.0 ms · ~4.2 GB/s | one 64-bit compare per 8 elements |
| `tula_validate_strict`, the same bytes as U8 | 1 µs | no value rule: sizes and padding only |
| `tula_validate_strict`, 200 tensors | 54.8–62.2 µs | 1.6.2 on the same machine and run: 54.7–63.4 µs (unchanged; this machine reads ~30% slower than 1.2.0's numbers above) |

### 1.8.0: FP8 and INT4

2²⁰ elements, `make bench`, three runs (the range). FP8 converts one element per
call in integer arithmetic (ADR 0010); the shared F16 path's inline fast path
isn't used for E5M2 yet (1.9.0 changed both; see below).

| Op | 1.8.0 | Notes |
|---|---:|---|
| `tula_e4m3_pack` | 16.3–16.7 ms · 62–64 Melem/s | f64 → E4M3, round to nearest even, no saturation |
| `tula_e4m3_unpack` | 8.7–9.2 ms · 113–119 Melem/s | exact |
| `tula_e5m2_pack` | 21.3–22.6 ms · 46–49 Melem/s | the shared narrow, (E, M) = (5, 2) |
| `tula_e5m2_unpack` | 12.7–13.4 ms · 78–82 Melem/s | |
| `tula_int4_pack` | 18.4–20.5 ms · 51–56 Melem/s | Q4_0's rule in f64, blocks of 32 |
| `tula_int4_unpack` | 8.0–8.8 ms · 118–130 Melem/s | code × the block's scale |
| strict, the 16 MiB BOOL tensor | 4.0–4.1 ms | unchanged by INT4's rule (one byte per odd-length INT4 tensor); one first run read 8.2 ms |

**Signing and verifying big files is bound by sigil's SHA-512.** At ~18 MB/s, a
14 GB (7B BF16) checkpoint takes about 25 minutes to sign and 13 to verify. tula
adds only the write and one mapping. Crypto is sigil's (ADR 0001), so the fix is
there: a tuned SHA-512 runs at hundreds of MB/s. It is filed with sigil
(`2026-11-09-anukulana-sha512-throughput-bounds-big-file-signing.md`, ~19 MB/s
on this machine).

### 1.9.0: throughput

`make bench` builds of 1.8.0 and 1.9.0, run alternately on the same machine,
three runs each (the range). Every row's output is the same in both: the suites
check each new path against the definition it replaces, and a cross-version
diff over random inputs matched 1.8.0 on every array helper, builder, strict
verdict and lookup.

**The array helpers**, 2²⁰ elements, one thread:

| Op | 1.8.0 Melem/s | 1.9.0 Melem/s | | How |
|---|---:|---:|---:|---|
| `tula_e4m3_unpack` | 121–127 | 581–585 | 4.7× | 256-entry table, 8 codes per load |
| `tula_e5m2_unpack` | 84–88 | 577–584 | 6.7× | the same |
| `tula_int8_dequant` | 411–432 | 590–596 | 1.4× | its table, 8 codes per load |
| `tula_ternary_unpack` | 358–379 | 617–621 | 1.7× | a byte's 4 trits from a 256-entry table |
| `tula_int4_unpack` | 134–139 | 353–355 | 2.6× | each block's 16 products by one `f64v_scale`, a byte at a time |
| `tula_nf4_unpack` | 244–256 | 374–375 | 1.5× | the same |
| `tula_f32_unpack` / `f16` / `bf16` | 140–147 | 216–219 | 1.5× | one loop per format, one range test |
| `tula_f32_pack` / `f16` / `bf16` | 101–116 | 151–154 | 1.4× | the same, rounding without a branch |
| `tula_e4m3_pack` | 66–70 | 149–150 | 2.2× | inline rounding below the top exponent |
| `tula_e5m2_pack` | 50–52 | 152–154 | 3.0× | the same |
| `tula_int4_pack` | 58–61 | 60–61 | — | unchanged (the division per element) |
| `tula_nf4_pack` | 25–26 | 26 | — | unchanged (the codebook search) |

One core's memory bandwidth bounds the byte-sized formats: a plain 8-byte copy
of the same output runs at about 570 Melem/s.

**`tula_unpack_par`** (ADR 0012), 2²⁴ elements (128 MiB of f64 out):

| dtype | 1 thread | 2 | 4 | 8 |
|---|---:|---:|---:|---:|
| BF16 | 208–215 | 409–414 | 738–771 | 958–976 |
| E4M3 | 543–567 | 1,027–1,062 | 1,880–1,941 | 1,905–1,996 |
| INT8 | 544–564 | 1,021–1,063 | 1,849–1,925 | 1,964–1,994 |
| INT4 (block 32) | 333–347 | 633–659 | 1,173–1,190 | 1,477–1,492 |
| NF4 (block 64) | 364–366 | 680–691 | 1,228–1,311 | 1,596–1,612 |

Melem/s. Past 4 threads the byte formats are bound by memory bandwidth (about
16 GB/s of f64 written). A thread start costs about 29 µs (a 2 MiB stack mapped,
then the clone) and a join about 6 µs, so 8 threads cost a call about 0.25 ms.
That is why each thread gets at least 65,536 elements. At that minimum, BF16
gains from 131,072 elements (629 → 413 µs on 2 threads), and E4M3 breaks even
there and gains from 262,144 (458 → 264 µs on 4).

**Per-call costs**:

| Op | 1.8.0 | 1.9.0 | How |
|---|---:|---:|---|
| `tula_validate`, 200 tensors | 2.71–2.78 µs | 2.39–2.43 µs | the name's NUL found a word at a time |
| `tula_validate_strict`, 200 tensors | 50.6–51.3 µs | 38.9 µs | the duplicate sort compares hashes inline |
| `tula_validate_strict`, 256 tensors | 86.5–89.3 µs | 59.1–59.3 µs | the same |
| `tula_builder_add` | 187–198 ns | 154–160 ns | the name measured once, copied a word at a time |
| `tula_builder_add_checked` | 210–223 ns | 137–142 ns | no second measure of the name |
| `tula_index_new`, 256 long names | 83.5–84.8 µs | 66.7–67.2 µs | the sort |
| `tula_index_find`, short names | 249–260 ns | 216–231 ns | the query built in one measured pass |
| `tula_index_find`, long names | 617–635 ns | 614–615 ns | unchanged: the key's hash dominates |
| `tula_find_name`, long names | 1.97–2.09 µs | 1.98–2.00 µs | unchanged |
| `tula_builder_set_meta` | 731–772 ns | 776–803 ns | no change on its path: code layout |

`f64v` is cyrius's SIMD array arithmetic. It has no integer and float
conversion, no shifts, masks or gathers, so the conversions can't use it; NF4
and INT4 use `f64v_scale` for their block products, always over 16 elements
(see ADR 0012 on the open cyrius issue for odd lengths).

### 1.9.1: NF4 pack and the 16-bit unpacks

1.9.0 and 1.9.1 `make bench` builds, alternately, three runs each (the range);
the outputs are the same (cross-version diff and `kernels.tcyr`).

| Op | 1.9.0 | 1.9.1 | How |
|---|---:|---:|---|
| `tula_nf4_pack` (2²⁰, block 64) | 23–24 Melem/s | 60–63 Melem/s | 15 exact thresholds, four comparisons per code |
| `tula_f16_unpack` (2²⁰) | 195–205 | 336–351 | a per-call table of the 65,536 codes, from 262,144 elements |
| `tula_bf16_unpack` (2²⁰) | 196–205 | 345–361 | the same |
| `tula_unpack_par`, BF16 2²⁴, 1 / 2 / 4 / 8 threads | 195–204 / 375–401 / 716–754 / 805–953 | 445–471 / 815–871 / 1,468–1,509 / 1,373–1,585 | each slice of 262,144 or more builds its own table |

Every other row was unchanged within the runs' spread. Below 262,144 elements
the 16-bit unpacks run 1.9.0's loop: the table costs about 0.4 ms to build and
map, which a smaller tensor wouldn't win back.

### 1.10.0: the protected open

The 100 MB, 200-tensor file, `make bench`, page-cache-warm:

| Op | 1.10.0 | Notes |
|---|---:|---|
| `tula_open_protected` | 11.8 ms · ~8.9 GB/s | not fs-verity here: a private copy, then validation; the same cost as `read (heap)` |
| `tula_open_mmap` | 11 µs | for comparison: maps lazily, and each page faults in on first touch |
| `make bigfile`: `tula_open_protected` of 2.36 GB | 306 ms · ~7.7 GB/s | a private copy past the 2 GiB allocation cap |

On an fs-verity file, the protected open costs what `tula_open_mmap` does, plus
one `ioctl`. The kernel then verifies each page against the file's Merkle tree
the first time it's read.

### Added in 1.5.0

| Op | 1.5.0 | Notes |
|---|---:|---|
| `tula_index_new`, 256 long names | 86 µs | canonical keys + hash + heapsort, one mapping |
| `tula_index_find`, 256 short names | 259 ns | vs `tula_find` 790 ns |
| `tula_index_find`, 256 long names | 581 ns | vs `tula_find_name` 2.1 µs (key hash + confirm) |
| every name of 4,096 tensors | 3.1 ms by index (build included) | vs 44.8 ms by `tula_find_name`: 14.5× |
| `make realmodels` (5 inventories) | 5.9 s | dominated by signing ~28 MB through sigil's SHA-512 |

The index gains with n, since scans are O(n) and the index O(log n). The
per-lookup constant (~250 ns short, ~580 ns long) is query canonicalization,
the hash, and the full-name confirm. A long name also pays for its FNV-1a key
and the names-table record search. In `make realmodels`, Mixtral's 995 tensors
build in ~0.4 ms and resolve at ~0.8 µs each.

### Added in 1.6.0

| Op | 1.6.0 | Notes |
|---|---:|---|
| `tula_builder_set_meta` | ~850 ns | per pair (64 pairs, 31-byte values): key + UTF-8 checks, binary search, copies |
| `tula_meta_get` | ~430 ns | per lookup among 64 pairs: table recognition + binary search |

Metadata adds about 400 bytes per file in `make realmodels` (3 pairs), and
nothing measurable to its run.

Earlier result (1.0.0, cyrius 6.3.27, tmpfs `/tmp`, ms resolution): write 34 ms,
read 41 ms, mmap open < 1 ms, mmap scan 4 ms. That harness measured file I/O only.

## Reading the numbers

- **mmap is the scalable path.** `tula_open_mmap` costs about 10 µs regardless of
  file size: it maps, it doesn't copy. A consumer reading a few tensors out of a
  multi-GB checkpoint pays only for the pages it touches. Map only files nobody
  else writes (`SECURITY.md`).
- **`read (heap)` copies the whole file**, so its cost is linear in size; use it
  for small files, for files others can write, or when you need an owned buffer.
- **validate is O(tensors), not O(bytes)**: ~12 ns per entry.
- **Unpack big tensors with `tula_unpack_par`** (1.9.0): the serial helpers top
  out near one core's memory bandwidth, and 4–8 threads give 3–5× more.
- **`tula_find` is a linear scan**: ~3 ns per entry. For many lookups on one
  file, build the name index (1.5.0): looking up every tensor is then
  O(n log n) instead of O(n²).
