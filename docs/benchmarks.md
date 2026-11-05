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
