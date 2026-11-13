# 0013 — A protected open: zero-copy for fs-verity files, a private copy otherwise

**Status**: Accepted
**Date**: 2026-11-12

## Context

`tula_open_mmap` maps a file read-only and validates the mapping. A mapping is
live, though (audit 2026-11-04, D-7). Another process that rewrites the file in
place after validation changes bytes tula has already checked and a signature
has already covered. One that truncates it makes the reader's next touch of
the missing tail raise SIGBUS. Writers that do this include `cp` over an
existing file (`O_TRUNC`, then write), a download still in progress, `dd`, an
editor saving in place, or another user with write permission. Replacing the
file by rename, as tula's own writers do, doesn't: the mapping keeps the old
inode.

Since 1.1.2 this is documented, and the advice is to map only files nobody else
writes, or to read a private copy. The roadmap asked for research: a protected
open that keeps zero-copy for the common case, through a Linux read lease or a
copy into an anonymous mapping. What was found:

- **A read lease** (`F_SETLEASE`, `F_RDLCK`) is granted only while nobody has
  the file open for writing. It doesn't stop a writer, though: a writer's open
  blocks for `lease-break-time` (45 s by default) and then proceeds.
  - The holder is told with SIGIO, whose default action ends the process. A
    library can't install the handler that would be needed.
  - Leases are Linux-only, and only for the file's owner (or `CAP_LEASE`).
- **The immutable attribute** (`chattr +i`) refuses new opens for writing. It is
  enforced on writers already open only on some filesystems: ext4 does it
  (commit 02b016ca7f99), tmpfs doesn't (a 2025 patch to make it was turned
  down), and a VFS-wide fix from 2019 isn't confirmed merged. Setting it also
  needs `CAP_LINUX_IMMUTABLE`.
- **fs-verity** (ext4 with `-O verity`, f2fs, btrfs) is a real guarantee:
  - Enabling it fails with `ETXTBSY` while anything has the file open for
    writing, a writable mapping included.
  - Afterwards, opening the file for writing and `truncate()` fail with
    `EPERM`, and verity can't be turned off.
  - The kernel verifies every page against the file's Merkle tree on read; a
    page that fails gives SIGBUS through a mapping.
  - `FS_IOC_GETFLAGS` reports it as `FS_VERITY_FL` (0x00100000).

  For a checkpoint, which is written once, it fits.
- **A reflink clone** (`FICLONE` into a nameless file) is a copy-on-write
  snapshot at almost no cost, but only on btrfs, XFS and similar. It needs a
  writable directory on the same filesystem. APFS has `clonefile` instead.
  Neither this machine (ext4) nor CI (ext4, APFS) can test the Linux path.
- **A copy** into an anonymous private mapping protects on every system. It
  costs one read of the file and memory equal to its size.

## Decision

**Add `tula_open_protected(path)`.** It returns a reader whose bytes nothing done
to the file afterwards can change, or 0. Release it with `tula_close_mmap`, as a
mapping.

- **An fs-verity file** (Linux: `FS_VERITY_FL` from `FS_IOC_GETFLAGS` on the
  opened fd) is mapped read-only, zero-copy, as `tula_open_mmap` does. The
  kernel refuses every write and truncation, and no writer can exist.
- **Any other file** is read into a private anonymous mapping and validated
  there.
  - Any size up to `TULA_READ_MAX_BYTES`; there is no 2 GiB allocation cap.
  - A writer racing the read can only produce bytes that fail validation (and
    a signature check), or bytes that are then fixed.
  - A truncation is a short read, and the file is rejected. Neither can fault
    the reader.
- **The check is made on the descriptor that is then mapped or read,** before
  the header is read, so a rename between the check and the use can't swap the
  file underneath.
- **The immutable attribute isn't trusted** for zero-copy, since enforcement on
  open writers differs by filesystem. On macOS and other systems the open
  always copies.
- **fs-verity is the file's owner's to enable,** typically the model store
  after a download, not the codec's (ADR 0001). tula only reads the flag.

## Consequences

- **Positive**
  - A loader that doesn't control where its files live gets validation and
    signature checks that hold for as long as it uses the reader.
  - A store that seals its files with fs-verity keeps zero-copy. Verity also
    adds a kernel-checked integrity layer under tula's signature.
  - `tula_open_mmap` and `tula_read_file*` are unchanged.
- **Negative**
  - Without fs-verity the protection costs a full read and memory equal to the
    file, which matters for a large model. The loader chooses: `tula_open_mmap`
    when it trusts the file's location, `tula_open_protected` when it doesn't.
  - A verity mapping can still SIGBUS if the storage returns corrupt data. That
    holds for any mapping of a failing disk, but here the data never changes.
  - The zero-copy branch runs only where fs-verity is available. Locally it is
    tested by forcing the branch on an ordinary file. CI makes an ext4 image
    with `-O verity` where the runner allows it, and checks the real flag
    there.
- **Neutral**
  - A reflink snapshot (btrfs/XFS `FICLONE`, APFS `clonefile`) could later give
    zero-copy protection to unsealed files on those filesystems, beside this
    function.
  - A way to ask whether a file would be copied could help a loader plan
    memory. It isn't added: a path-based check would race the open, and the
    loader can pick the call instead.

## Alternatives considered

- **A read lease:** rejected. It only delays a writer, its break signal ends a
  process that has no handler, and it needs the file's owner. It also exists
  only on Linux.
- **Trusting `chattr +i`:** rejected. Some filesystems let a writer that opened
  before the flag was set keep writing, so the flag alone doesn't prove the
  bytes are fixed.
- **Changing `tula_open_mmap` to protect:** rejected. It would add a copy to
  every caller of a frozen function that today maps for free, many of which
  open their own files.
- **tula enabling fs-verity itself** (a `tula_seal_file`): rejected for now.
  Enabling is irreversible and needs a filesystem feature, and sealing a file
  is the store's decision, not the codec's.
- **Copying through `MAP_PRIVATE` and forcing every page private**
  (`MADV_POPULATE_WRITE`): no cheaper than reading. A truncation during the
  populate can fault, where `read()` just returns short.
