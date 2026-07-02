# Architecture Decision Records

Decisions about chitra — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | [`docs/architecture/`](../architecture/README.md) | *What non-obvious constraint is true about the code?* |
| Guide | [`docs/guides/`](../guides/getting-started.md) | *How do I do X?* |

Durable rationale belongs in an ADR; non-obvious code invariants belong in an architecture note. Volatile state — versions, sizes, counts, in-flight work — lives only in [`docs/development/state.md`](../development/state.md), never here.

## Index

| ADR | Status | Subject |
|---|---|---|
| [0001](0001-fork-kii-png-decoder.md) | Accepted | Fork kii's PNG decoder into the chitra package (one-time fork, manual backports, no live dependency) |
| [0002](0002-security-model.md) | Accepted | Security model: untrusted-image input + library/no-emit posture |
| [0003](0003-mabda-abi-compatibility.md) | Accepted | mabda ABI compatibility: 16-byte GpuErr-compatible `ChitraErr` + append-only `ChitraImage` |
| [0004](0004-jpeg-decode-model.md) | Accepted | JPEG decode model: JFIF baseline sequential Huffman 8-bit only; integer fixed-point IDCT; non-baseline modes cleanly rejected |
