# Architecture Decision Records

Decisions about tula — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| API reference | [`docs/api.md`](../api.md) | *What is the public surface and its contract?* |
| Architecture note | `docs/architecture/` (when earned) | *What non-obvious constraint is true about the code?* |

Durable rationale belongs in an ADR; the public contract lives in `docs/api.md` (frozen at v1.0 — see [`STABILITY.md`](../../STABILITY.md)). Volatile state — versions, sizes, counts, in-flight work — lives only in [`docs/development/state.md`](../development/state.md), never here.

## Index

| ADR | Status | Subject |
|---|---|---|
| [0001](0001-tula-scope.md) | Accepted | tula scope: the weight-file codec, nothing more |
| [0002](0002-quant-scales-as-sidecar-tensors.md) | Accepted | Quantization scales are sidecar tensors, not an entry field (no format-version bump) |
| [0003](0003-api-freeze-at-v1.md) | Accepted | Freeze the public API and on-disk format (v1) at 1.0 |
| [0004](0004-long-names-via-a-names-table.md) | Accepted | Long tensor names live in a names-table tensor; the entry holds a key (no format-version bump) |
| [0005](0005-f32-f16-bf16-dtypes.md) | Accepted | F32, F16 and BF16 dtypes, converted from f64 in integer arithmetic |
| [0006](0006-streaming-atomic-writes.md) | Accepted | Big files: stream from caller memory, sign the written file, replace atomically |
| [0007](0007-sorted-name-index.md) | Accepted | The name index is a sorted array, not a hash table |
| [0008](0008-file-metadata-table.md) | Accepted | File metadata lives in a sorted key/value table tensor (no format-version bump) |
| [0009](0009-integer-and-boolean-dtypes.md) | Accepted | Integer and boolean dtypes: I16, I32, I64, U8 and BOOL, stored raw |
| [0010](0010-fp8-e4m3-e5m2-dtypes.md) | Accepted | FP8 dtypes: OCP E4M3 and E5M2, converted from f64 without saturation |
| [0011](0011-int4-blockwise-codes-with-scale-sidecar.md) | Accepted | INT4: signed 4-bit codes, with blockwise scales in an ADR 0002 sidecar |
| [0012](0012-parallel-unpack.md) | Accepted | Parallel unpack: one call over every unpack helper, threads started per call |
| [0013](0013-protected-open.md) | Accepted | A protected open: zero-copy for fs-verity files, a private copy otherwise |
| [0014](0014-shard-sets.md) | Accepted | Sharded checkpoints: a signed manifest of shard digests, in the codec |
