# 0006 — Big files: stream from caller memory, sign the written file, replace atomically

**Status**: Accepted
**Date**: 2026-11-04

## Context

`tula_serialize` builds the whole file in one allocation, and the cyrius stdlib
caps a single allocation at 2 GiB (`ALLOC_MAX`). So no file over 2 GiB can be
written, and a 7B-parameter checkpoint is 14 GB in BF16. The reader side is
already fine: `tula_open_mmap` maps any size up to `TULA_READ_MAX_BYTES` (1 TiB),
but `tula_read_file` allocates, so it has the same cap (audit D-3, D-9).

Signing is the hard part. The v1 signature is Ed25519 over `[0, sig_off)` as
**one message** (frozen, ADR 0003), and sigil's `ed25519_sign` takes that message
as one contiguous buffer. The roadmap assumed a streamed, signed file would need a
new multi-part sign from sigil.

`tula_write_file` is also not crash-safe: it truncates the target first, so a
failure part-way leaves a truncated file (D-8). The readers reject that file, but
the old model is gone.

## Decision

**The builder streams its file straight to disk, signs it by mapping what it
wrote, and replaces the target atomically.** No format change, and no sigil
change.

- **`tula_builder_write_file(b, path)`** writes exactly the bytes
  `tula_builder_finish(b)` would produce, without ever holding them. The header,
  manifest and names table go through a 64 KiB staging buffer, a private mapping
  released afterwards. Each tensor's payload is written **directly from the
  caller's buffer**, with zero padding after it. Memory use is O(staging +
  names), not O(file).
- **`tula_builder_write_file_signed(b, path, sk)`** writes the content
  `[0, sig_off)`, maps those bytes read-only from the file just written, runs
  sigil's `ed25519_sign` over the mapping, then appends the 64-byte signature.
  `ed25519_sign` streams its message through SHA-512 without copying it, so the
  mapping is the whole cost and the page cache holds the bytes, not the heap. The
  result is byte-identical to `tula_builder_finish_signed`: Ed25519 is
  deterministic.
- **Atomic replace.** Both writers create a sibling temp file `<path>.tula-<16
  hex>.tmp`:
  - The 64-bit random suffix comes from `random_bytes` (the kernel's `getrandom`).
  - It is created with `O_CREAT|O_EXCL`, which never opens or follows anything
    that already exists, so a planted name or symlink is retried under a new
    name.
  - Its mode is the existing target's mode (or 0644 under the umask), so it is
    never more permissive than the result.

  The writer then writes, `fsync`s and closes it, renames it over `path`, and
  `fsync`s the directory (best effort). On **any** failure the temp is unlinked
  and `path` is untouched. A crash leaves the old file or the new one, never a
  mix. A symlink at `path` is replaced, not written through, as with the
  stdlib's `file_write_atomic`.
- **`tula_write_file_atomic(path, buf, len)`** is the same guarantee for an
  in-memory buffer, delegating to the stdlib's `file_write_atomic`.
- **Reading big files on the heap.** `tula_file_len(path)` returns the total a
  file's header declares, after checking the file really holds it.
  `tula_read_file_into(path, buf, cap)` reads into the caller's buffer. A caller
  can size a buffer, reuse it across files, or provide one bigger than 2 GiB
  (e.g. an anonymous mapping). It also avoids a heap buffer that the bump
  allocator could never free.

## Consequences

- **Positive** — checkpoints of any size up to the 1 TiB cap can be written,
  signed and read. End to end on 2.42 GB: `make bigfile` (unsigned, a CI gate,
  seconds) and `make bigfile-signed` (signed and verified, run locally: minutes,
  because sigil's SHA-512 runs at ~18 MB/s). The bytes are identical to the
  in-memory writer's, so every reader, verifier and test applies. A crashed or failed write never destroys the previous file. No new
  sigil surface is needed.
- **Negative** — the streaming writers `fsync`, which costs time a plain `write`
  doesn't. Signing reads the whole file back through the page cache, about one
  extra pass. The writer needs `mmap` on the target (every cyrius Linux and
  macOS target); without it the signed writer returns an error. Between writing
  and mapping, a process with write access to the temp file could change what
  gets signed. It is created with the target's mode and a random name, so only
  the file's owner can.
- **Neutral** — `tula_write_file` keeps its frozen truncate-and-write semantics;
  callers who want crash safety use `tula_write_file_atomic`.

## Alternatives considered

- **Multi-part Ed25519 from sigil** (sign while streaming): rejected for now. It
  needs a new sigil API, and tula would still need two passes (Ed25519 hashes the
  message twice: once for the nonce, once for the challenge), so it saves nothing
  over mapping the written file.
- **Ed25519ph (pre-hashed)**: rejected. It is a different signature scheme, so it
  would be a format break.
- **Raising `ALLOC_MAX`** or allocating the file with `mmap_anon`: rejected. It
  still holds the whole file in memory (14 GB for a 7B BF16 model) just to write
  it.
- **Using the stdlib's private temp-file helper** (`_io_tmp_open`): rejected. It
  is a private symbol that can change at any toolchain bump. The pattern is
  rebuilt from public calls (`file_open` with `O_EXCL`, `random_bytes`, `xstat`,
  `xfsync`, `file_rename`, `xunlink`).
