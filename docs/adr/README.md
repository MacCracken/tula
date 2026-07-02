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
