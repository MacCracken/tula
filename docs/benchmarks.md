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

**Signing and verifying big files is bound by sigil's SHA-512.** At ~18 MB/s, a
14 GB (7B BF16) checkpoint takes about 25 minutes to sign and 13 to verify. tula
adds only the write and one mapping. Crypto is sigil's (ADR 0001), so the fix is
there: a tuned SHA-512 runs at hundreds of MB/s. It's on the roadmap as a
cross-repo ask.

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

Earlier result (1.0.0, cyrius 6.3.27, tmpfs `/tmp`, ms resolution): write 34 ms,
read 41 ms, mmap open < 1 ms, mmap scan 4 ms. That harness measured file I/O only.

## Reading the numbers

- **mmap is the scalable path.** `tula_open_mmap` costs about 10 µs regardless of
  file size: it maps, it doesn't copy. A consumer reading a few tensors out of a
  multi-GB checkpoint pays only for the pages it touches. Map only files nobody
  else writes (`SECURITY.md`).
- **`read (heap)` copies the whole file**, so its cost is linear in size; use it
  for small files, for files others can write, or when you need an owned buffer.
- **validate is O(tensors), not O(bytes)**: ~14 ns per entry.
- **`tula_find` is a linear scan**: ~3 ns per entry now. A checkpoint with
  thousands of tensors, looked up one name at a time, is still O(n²) overall. A
  name index is on the roadmap.
