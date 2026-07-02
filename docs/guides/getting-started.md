# Getting started

> **Last Updated**: 2026-07-01

Build and test tula, then write and read a signed weight file. tula is a
**library** (no CLI binary) — the "run" step is the consumer example.

## Prerequisites

- **Cyrius toolchain** — the version is pinned in `cyrius.cyml` under
  `[package].cyrius` (the pin is the single source of truth; run `cyrius --version`
  to confirm your install matches).
- **`sigil`** — the Ed25519 dependency. Local dev resolves it via `path = "../sigil"`
  (clone `sigil` next to `tula`); CI resolves it via git+tag.
- Linux x86_64 is the primary target.

## Build and test

```sh
make build     # link-check the library via programs/smoke.cyr
make test      # run the CPU suites in tests/tcyr/
make dist      # regenerate dist/tula.cyr (the bundle consumers pull)
```

First build fetches deps into `lib/` (a gitignored build artifact) and resolves
`sigil`. Subsequent builds are cached.

Optional harnesses:

```sh
make example   # end-to-end consumer (examples/consumer.cyr)
make fuzz      # reader fuzz harness, >10^6 iterations
make bench     # write/read/mmap throughput
```

## Write a weight file

A minimal writer: accumulate tensors in a builder, then serialize (optionally
signing). `f64` values are IEEE-754 **bit patterns** in `i64` — build them with
the `f64_*` builtins.

```cyrius
include "src/lib.cyr"

fn main(): i64 {
    alloc_init();

    # one f64 [3] tensor
    var shape = alloc(8);
    store64(shape, 3);
    var data = alloc(24);
    store64(data + 0, f64_from(7));
    store64(data + 8, f64_from(8));
    store64(data + 16, f64_from(9));

    var b = tula_builder_new();
    tula_builder_add(b, "w", TULA_DT_F64, shape, 1, data, 24);
    var buf = tula_builder_finish(b);                 # unsigned
    tula_write_file("/tmp/model.tula", buf, tula_total_len(buf));
    return 0;
}

fn _entry(): i64 { var r = main(); syscall(60, r); return 0; }
_entry();
```

To sign instead, generate a key with `sigil` and call
`tula_builder_finish_signed(b, sk)` — the 64-byte Ed25519 signature covers the
whole file `[0, sig_off)`.

## Read a file (untrusted)

The reader treats every file as hostile. `tula_read_file` validates structure
before returning a handle; `tula_open`/`tula_validate` do the same for an
in-memory buffer.

```cyrius
var r = tula_read_file("/tmp/model.tula");
if (r == 0) { return 1; }                             # malformed -> rejected

# if signed, check authenticity before trusting the data
# if (tula_verify(r, pk) != TULA_SIG_OK) { return 1; }

var e = tula_find(r, "w");
if (e == 0) { return 1; }
if (tula_entry_payload_ok(e) != 1) { return 1; }      # guard before unpack
var p = tula_entry_data(r, e);                        # in-bounds, zero-copy
```

For large files prefer `tula_open_mmap` (zero-copy; sub-millisecond regardless of
size) + `tula_close_mmap`. See [benchmarks](../benchmarks.md).

## Quantized tensors

The dtype helpers pack/unpack ternary / int8 / NF4; scales ride in a
`"<name>.scale"` sidecar tensor ([ADR 0002](../adr/0002-quant-scales-as-sidecar-tensors.md)).
Before unpacking a foreign quantized tensor, call `tula_entry_payload_ok(e)`. See
[`docs/api.md`](../api.md) for the full surface and
[`examples/consumer.cyr`](../../examples/consumer.cyr) for a complete
quantize→sign→read→verify→dequant loop.

## Consume tula from another Cyrius repo

Downstream repos pull the bundle via a `[deps.tula]` git-tag entry and supply
their own `sigil` (the bundle leaves `ed25519_*` unresolved — the standard
consumer-bundle pattern):

```toml
[deps.tula]
git = "https://github.com/MacCracken/tula.git"
tag = "1.0.0"
modules = ["dist/tula.cyr"]
```

Then `include "lib/tula.cyr"` alongside your stdlib and `sigil` includes.

## Next

- Public API: [`docs/api.md`](../api.md) · stability: [`STABILITY.md`](../../STABILITY.md)
- Design decisions: [`docs/adr/`](../adr/) · code invariants: [`docs/architecture/`](../architecture/)
- Roadmap: [`docs/development/roadmap.md`](../development/roadmap.md)
