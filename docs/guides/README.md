# Guides

Task-oriented how-tos for working on or with tula. If you have a clear goal
("build and test tula", "write and read a weight file", "consume tula from
another Cyrius repo"), a guide gets you there.

## Index

- [Getting started](getting-started.md) — build + test tula, write and read a
  signed weight file end-to-end, and consume `dist/tula.cyr` from a downstream
  Cyrius project.

For a complete *runnable* example covering the write→sign→read→verify→unpack
loop, see [`../examples/`](../examples/) (source at
[`examples/consumer.cyr`](../../examples/consumer.cyr)).

## What doesn't belong here

- **Decisions** → [`../adr/`](../adr/)
- **Constraints and quirks** → [`../architecture/`](../architecture/)
- **Public API reference** → [`../api.md`](../api.md)
- **Runnable code** → [`../examples/`](../examples/)
