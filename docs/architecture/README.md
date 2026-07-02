# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from
the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides (those live in
[`../guides/`](../guides/)). An item here describes *how the world is*, not *what
we chose* or *how to do something*.

## Items

- [001 — Flat-module layout: stdlib includes live only in `lib.cyr`](001-flat-module-layout.md)
  — affects every `src/*.cyr` module and the `dist/tula.cyr` bundle; explains the
  LSP "undefined symbol" false-positives you'll see in standalone files.
- [002 — Reader accessors assume a validated buffer](002-accessors-require-validated-buffer.md)
  — affects every consumer: `tula_open`/`tula_validate` is the trust gate; the
  accessors and `tula_verify` are memory-safe **only** on a buffer that passed it.
