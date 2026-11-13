# 0012 — Parallel unpack: one call over every unpack helper, threads started per call

**Status**: Accepted
**Date**: 2026-11-12

## Context

The 1.9.x goal is that the codec is never the slow part of loading a model. A
loader reads a tensor's payload (mapped, so the read is free) and unpacks it to
f64 with a dtype helper. In 1.8.0 those helpers ran at 80–420 Melem/s on one
core. A 7B checkpoint in BF16 is 7·10⁹ elements: about 50 s of unpacking at
137 Melem/s.

1.9.0 makes the helpers themselves faster (tables, one loop per format), and
on one core the byte-sized formats now come close to a plain copy of their f64
output (~570 Melem/s on the reference machine). Past that, one core's memory
bandwidth is the limit, and more cores are the only lever left.

The helpers are pure and elementwise. Each output depends on one code (and its
block's scale), and they keep no state between calls. A tensor can therefore
be cut into slices, each unpacked on its own thread, with the serial output
exactly. The questions are the API's shape and who owns the threads.

The cyrius stdlib (`lib/thread.cyr`) has `thread_create(fp, arg)` and
`thread_join(t)`:
- Each create maps a 2 MiB stack and clones a thread.
- It also allocates a 24-byte handle and a 4 KiB TLS block on the bump
  allocator, which has no free.
- `THREADS_CONCURRENT` says whether the target really runs a second thread: 1
  on Linux, macOS and Windows; 0 on agnos and cx.
- There is no portable CPU count.

## Decision

**Add `tula_unpack_par(dtype, src, n, scales, block, dst, nthreads)` in a new
module, `src/par.cyr`.** It runs the dtype's serial helper over contiguous
slices on up to `nthreads` threads, and its output is the serial helper's, bit
for bit.

- **One call, every helper.** It covers F32, F16, BF16, F8_E4M3, F8_E5M2, INT8
  (the one f64 scale at `scales`), NF4 and INT4 (one f64 scale per `block`
  elements) and TERNARY (i64 trits). A loader already dispatches on
  `tula_entry_dtype`, so one call replaces a nine-way switch.
- **Returns n**, or −1, writing nothing, for:
  - a dtype with no unpack helper: F64, the raw integers, BOOL, unknown codes;
  - `n < 0`;
  - `block <= 0` for NF4 or INT4.
- **Threads are started and joined per call.** There is no pool and no state
  between calls. The caller's thread unpacks the first slice and then joins the
  rest.
- **Slice boundaries are multiples of a unit**, so each slice starts on a
  whole byte of codes and a whole block of scales. The unit is 4 for ternary,
  the block for NF4 and INT4 (twice the block when it is odd), and 1 otherwise.
- **Every thread gets at least `TULA_PAR_MIN_CHUNK` (65,536) elements**, and a
  call uses at most `TULA_PAR_MAX_THREADS` (64) threads. A smaller tensor runs
  on the caller's thread alone, with no thread started. Both are tuning
  constants, outside the freeze: they change how a call is split, never what
  it writes.
- **Fallbacks.** A thread that fails to start has its slice run on the caller's
  thread. On a target where `THREADS_CONCURRENT` isn't 1, the whole call runs
  on the caller's thread. Both keep the output the same.
- **The caller picks `nthreads`.** A count below 1 counts as 1. tula doesn't
  probe the machine: the loader owns its thread budget, and the stdlib has no
  portable CPU count.
- Like the serial helpers, it trusts its arguments. A foreign entry and its
  sidecar are checked with `tula_entry_payload_ok` first.

## Consequences

- **Positive**
  - Loads are bound by memory bandwidth instead of one core. At 8 threads,
    2²⁴ elements unpack at about 970 Melem/s for BF16, 1,950 for E4M3, 1,980
    for int8, 1,480 for INT4 and 1,600 for NF4, against about 143, 124, 420,
    136 and 250 in 1.8.0 on one thread (`docs/benchmarks.md`). The byte
    formats get most of their gain by 4 threads.
  - The output can't depend on the thread count, by construction.
  - There is no format change and no change to any existing function.
- **Negative**
  - Each call pays its thread starts one after another: about 29 µs each on
    the reference machine (a 2 MiB stack mapped, then the clone), and about
    6 µs to join each (the stack unmapped). At 8 threads that is about
    0.25 ms a call, so a slice is at least 65,536 elements: that is 330 µs of
    BF16 on one core, 120 µs of E4M3.
  - Each thread started leaves its 4 KiB of stdlib bookkeeping on the bump
    allocator. A 7B model unpacked at 8 threads, one call per 2-D weight, keeps
    a few MB.
  - The first thread a process starts arms the allocator's lock for the rest of
    the process. Every later `alloc` takes an uncontended spinlock.
  - The function is frozen surface from 1.9.0.
- **Neutral**
  - Packing stays serial. It is the import path, not the load path, and INT8's
    per-tensor absmax would need a reduction across threads. A parallel pack is
    a later MINOR if an importer needs one.
  - A caller-owned worker pool, reusing threads across calls, can be added
    beside this function later without changing it.

## Alternatives considered

- **Nine `_par` siblings** (`tula_f16_unpack_par`, …): rejected. They add nine
  frozen functions where one does, and the loader would switch on the dtype to
  pick one anyway.
- **A worker pool** (`tula_pool_new(n)`, unpack on the pool,
  `tula_pool_free`): rejected for now. It adds a handle with lifetime rules,
  and a pool's threads wait in the background between calls. The per-call
  start is small next to a slice of 65,536 or more elements. If starts show up
  in a profile, a pool can come later.
- **tula picks the thread count:** rejected. It needs per-OS calls
  (`sched_getaffinity`, `sysctl`) the stdlib doesn't wrap, and the right count
  depends on what else the loader runs.
- **Vectorizing with the `f64v` builtins instead:** they don't fit the
  conversions. The `f64v_*` / `iv_*` builtins are arithmetic only: no integer
  and float conversion, no shifts, masks or gathers. tula's conversions are bit
  operations, and their speed-up comes from tables and specialized loops. The
  builtins do fit dequantization's multiply: NF4 and INT4 build each block's 16
  products with one `f64v_scale`, always over 16 elements. That length matters,
  because cyrius 6.7.18's `f64v_*` overrun an odd length by one element (open
  cyrius issue `2026-11-06-f64v-builtins-no-scalar-tail.md`).
