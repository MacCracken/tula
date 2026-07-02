# Examples

Runnable Cyrius programs that use the tula public API. Each has a top-of-file
comment explaining *why*, not just *what*.

## Index

- **[`consumer.cyr`](../../examples/consumer.cyr)** (`make example`) — a complete
  downstream consumer, the v1.0 "≥1 consumer green" gate and a CI check. It plays
  both roles end-to-end: a quantizing checkpoint **writer** (ternary-quantize →
  builder + `"<name>.scale"` sidecar → Ed25519 sign → write) and a hardened
  **loader** (read as untrusted → verify signature → `tula_entry_payload_ok`
  guard → unpack → dequant), plus a bit-exact plain-`f64` tensor.

> **Location note**: runnable examples live at the repo root under
> [`examples/`](../../examples/) so `make example` and CI can build them directly
> (the same convention as sibling references like `prajna`). This directory is the
> documented index into them.

## Running

```sh
make example        # builds examples/consumer.cyr -> build/tula_consumer and runs it
```

Expected tail:

```
RESULT: PASS — consumer loaded a signed, quantized model end-to-end
```

See [`docs/guides/getting-started.md`](../guides/getting-started.md) for the
write/read walkthrough and [`docs/api.md`](../api.md) for the full surface.
