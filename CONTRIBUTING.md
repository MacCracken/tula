# Contributing to tula

tula is the AGNOS **sovereign weight-file codec** — pure Cyrius, no external code
except `sigil` (Ed25519). It is a small library with a frozen v1 on-disk format
and many downstream consumers, so the bar is **correctness, a stable format, and
a hardened reader**.

## Ground rules

- **Pure Cyrius, one dep.** The only external dependency is `sigil` (the crypto
  boundary). No C, no FFI, no other libraries — a change that pulls one in won't
  be accepted ([ADR 0001](docs/adr/0001-tula-scope.md) keeps tula the codec and
  nothing more).
- **The format is a contract.** The on-disk layout is **v1** and frozen
  ([STABILITY.md](STABILITY.md)). A layout change is a `TULA_VERSION` bump — a
  MAJOR, coordinated event, never incidental ([ADR 0002](docs/adr/0002-quant-scales-as-sidecar-tensors.md)
  shows the lengths gone to *avoid* one).
- **The reader loads untrusted input.** Any change touching `tula_open` /
  `tula_validate` / the accessors must keep the hardening invariants (overflow-safe,
  bounds-checked, fail-loud) and stay green under the fuzzer. See
  [SECURITY.md](SECURITY.md) and the [audit](docs/audit/).
- **One change at a time.** Don't bundle unrelated changes.
- **Read [`CLAUDE.md`](CLAUDE.md) first** — the conventions and the flat-module
  layout will save you time.

## Building and testing

```sh
make build     # link-check the library (programs/smoke.cyr)
make test      # CPU test suites (tests/tcyr/*.tcyr)
make dist      # regenerate dist/tula.cyr (consumers pull this)
make example   # build + run the end-to-end consumer (examples/consumer.cyr)
make fuzz      # reader fuzz harness (>10^6 iterations)
make bench     # write/read/mmap throughput -> docs/benchmarks.md
cyrius lint src/*.cyr
cyrius fmt src/*.cyr --check
```

Every change must pass the same gates the CI enforces:

- **Tests green** — all `tests/tcyr/*.tcyr` suites. Add coverage for new behavior.
- **Fuzz clean** — anything touching the reader keeps `make fuzz` crash-free with
  every accepted buffer sound.
- **Lint clean** — `cyrius lint` emits no `warn ` lines.
- **Format clean** — `cyrius fmt --check` on all `src/`, `programs/`, `examples/`,
  and `tests/` files.
- **dist in sync** — if you touch a module in `cyrius.cyml [lib].modules`, run
  `make dist` and commit the regenerated `dist/tula.cyr` in the same commit (CI
  hard-fails otherwise).
- **Benchmark before claiming perf** — numbers from `make bench` in
  `docs/benchmarks.md`, or it didn't happen.

## Coding conventions

Cyrius has sharp edges; the ones that bite in tula:

- **Flat modules** — stdlib `include`s live **only** in `src/lib.cyr`; domain
  modules are include-free so `cyrius distlib` produces a compile-clean bundle. A
  new module goes in **both** `src/lib.cyr` and `cyrius.cyml [lib].modules`, in
  dependency order. The LSP flags cross-module symbols as "undefined" in a
  standalone file — that's the pattern; the build is authoritative. See
  [architecture note 001](docs/architecture/001-flat-module-layout.md).
- **f64 is an i64 bit pattern** — build values with the `f64_*` builtins; there
  are no float literals.
- **All fields are 8 bytes** via `load64`/`store64` at an offset;
  `load8`/`store8` + `memcpy` for byte payloads.
- **Module-scope `var X[N]` is N × u64 (8N bytes)**, not N bytes — a footgun when
  sizing buffers. Prefer `alloc()`.
- **Programs/tests** call `main()` from a bare top-level statement and exit via
  `syscall(60, rc)`.

Study the existing modules (`src/format.cyr` is the core) and skim
[`docs/architecture/`](docs/architecture/) before writing new code.

## Documentation

- **Decisions** → an ADR in [`docs/adr/`](docs/adr/) (use [`template.md`](docs/adr/template.md);
  never renumber).
- **Non-obvious constraints/quirks** → a numbered note in
  [`docs/architecture/`](docs/architecture/).
- **How-tos** → [`docs/guides/`](docs/guides/); **runnable examples** →
  [`examples/`](examples/) (indexed from [`docs/examples/`](docs/examples/)).
- **Public API** → keep [`docs/api.md`](docs/api.md) in step with the surface;
  a listed symbol is a stability commitment ([STABILITY.md](STABILITY.md)).
- **Changelog** → [Keep a Changelog](https://keepachangelog.com/); performance
  claims need numbers, breaking changes need a migration note, security fixes get
  a **Security** section.

## Cross-project requests

tula depends on `sigil` and the Cyrius toolchain. **These repos don't use the
GitHub issue tracker.** If tula needs something from `sigil` or Cyrius, draft a
backlog entry on *that repo's* `docs/development/roadmap.md` rather than filing an
issue.

## Commits & releases

The maintainer handles tagging and releases. Keep commits focused, message the
*why*, and make sure the working tree is green (lint + tests + dist-sync) before
you push. Security-sensitive reports go through [`SECURITY.md`](SECURITY.md), not
a public PR.

## Conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
