# 002 — Reader accessors assume a validated buffer

> **Last Updated**: 2026-07-01

**Affects**: every consumer of the reader — `tula_count`, `tula_entry`,
`tula_entry_*`, `tula_entry_data`, `tula_find`, `tula_is_signed`, and
`tula_verify`.

## The invariant

The reader accessors do **no** bounds checking of their own. They read fields at
fixed offsets and return pointers *into* the buffer, trusting that the structure
is sound. Soundness is established once, up front, by `tula_validate` (and the
`tula_open` wrapper that calls it, and the `tula_read_file` / `tula_open_mmap`
readers that end in `tula_open`).

So the contract is: **a buffer must pass `tula_open` / `tula_validate` before any
accessor is called on it.** On a validated buffer the accessors are provably
in-bounds — the fuzzer (`make fuzz`, >10⁶ iterations) checks exactly this: every
buffer `tula_open` accepts has every entry's payload range inside `[buf, buf+len)`.

Calling an accessor on a raw, un-validated buffer (e.g. one you built by hand, or
bytes you `mmap`'d without going through `tula_open`) can read out of bounds — the
accessor will happily dereference a lying `data_off`.

## Why `tula_verify` is in the same boat — and the `sig_len ∈ {0, 64}` pin

`tula_verify` reads a **fixed 64-byte** signature at `sig_off` and passes
`[0, sig_off)` to `sigil`'s `ed25519_verify`. That fixed-size read is only safe
because `tula_validate` pins `sig_len` to exactly `{0, 64}` and checks
`sig_off + 64 ≤ len`. If the validator accepted an arbitrary `sig_len` (say 32), a
validated-looking buffer could still make `tula_verify` read 32 bytes past the
end. The pin is what closes that gap — so `tula_verify`, like the other
accessors, is memory-safe **only** on a validated buffer.

## The rule

Untrusted bytes enter through `tula_open` / `tula_validate` / `tula_read_file` /
`tula_open_mmap` — never straight into an accessor. If you need the rejection
reason, call `tula_validate` and read the `TULA_ERR_*` code; `tula_open` collapses
all breaches to `0`.

Separately, before *unpacking* a foreign quantized tensor, call
`tula_entry_payload_ok(e)` — validation bounds `data_off`/`data_len` and `ndim`,
but not the `shape` dim *values*, so a lying shape could over-drive an unpack
helper's element count. See [ADR 0002](../adr/0002-quant-scales-as-sidecar-tensors.md)
and the [audit](../audit/2026-07-01-audit.md) (finding F-1).
