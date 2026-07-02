# tula — Benchmarks

Throughput of the file-I/O paths (`tula_write_file` / `tula_read_file` /
`tula_open_mmap`) on a large synthetic weight file. Harness: `programs/bench.cyr`
(`make bench`). Numbers are **indicative** — they depend on the machine, the
filesystem, and page-cache state, and are page-cache-warm (the file is written
then immediately read, so the read/mmap paths hit the OS cache). Re-run locally
with `make bench` for your own hardware.

## Method

- Payload: **200 f64 tensors × 512 KiB = ~100 MB** (`BN_TENSORS` × `BN_TSIZE`),
  each seeded with a non-zero per-page pattern so the file is not sparse.
- Each op is timed over `BN_ROUNDS` (3) rounds; the **minimum** latency is
  reported (least-noise estimate). MB/s = payload_bytes / min_latency.
- `mmap open` is the lazy map latency (no pages faulted). `mmap scan` touches one
  byte per 4 KiB page across the whole buffer to force fault-in — the mmap
  read-through-cache throughput.

## Results

Machine: **AMD Ryzen 7 5800H** (16 threads), Linux, tmpfs-backed `/tmp`.
Cyrius **6.3.27**. File: **104,886,464 bytes** (200 tensors). Page-cache warm.

| Op          | Latency (min) | Throughput  | Notes |
|-------------|--------------:|------------:|-------|
| write       | 34 ms         | ~3.06 GB/s  | serialize buffer already in RAM → `write(2)` |
| read (heap) | 41 ms         | ~2.54 GB/s  | full copy into a fresh heap buffer + validate |
| mmap open   | <1 ms         | —           | lazy map; **O(1)** in file size (the zero-copy win) |
| mmap scan   | 4 ms          | ~26 GB/s    | fault-in of a page-cache-resident file |

## Reading the numbers

- **mmap is the scalable path.** `tula_open_mmap` is sub-millisecond regardless of
  file size — it maps, it doesn't copy. A consumer that reads a few tensors out of
  a multi-GB checkpoint pays only for the pages it touches, not the whole file.
- **`read (heap)` copies the whole file**, so its cost is linear in size; use it
  for small files or when you need an owned, writable buffer.
- **`write` is memcpy-bound** (the serialized buffer is assembled in RAM by the
  builder, then written in one syscall).
- Validation (M3) runs on every `tula_open`; at this scale it is dominated by the
  copy/map cost — the per-entry checks are O(tensors), not O(bytes).
