# 001 — Flat-module layout: stdlib includes live only in `lib.cyr`

> **Last Updated**: 2026-07-01

**Affects**: every `src/*.cyr` module, `cyrius.cyml [lib].modules`, and the
generated `dist/tula.cyr` bundle.

## The invariant

`src/lib.cyr` is the **only** file that carries `include` directives. It includes
the stdlib set, then `sigil`, then the tula domain modules in dependency order.
The domain modules (`src/error.cyr`, `src/format.cyr`, `src/sign.cyr`,
`src/fileio.cyr`, `src/dtype.cyr`) are **flat** — they contain no `include` lines
at all and reference symbols defined in earlier-included modules as if they were
in the same scope.

This is deliberate. `cyrius distlib` produces `dist/tula.cyr` by **stripping
include lines and concatenating** the modules in `[lib].modules` order. If a
domain module carried its own stdlib includes, the concatenation would double-
include and fail to compile. Keeping includes solely in `lib.cyr` guarantees the
bundle is compile-clean for consumers.

## Consequences you will hit

- **The LSP reports "undefined variable/function" in a standalone `src/*.cyr`
  file.** For example, `src/format.cyr` uses `TULA_ERR_TOO_MANY` (defined in
  `src/error.cyr`) and the stdlib `alloc`/`load64`/`f64_*` builtins. Opened on its
  own, the language server can't see those definitions and flags them. **This is
  expected — the build is authoritative.** `make build` / `make test` compile the
  real include chain and will catch a genuine undefined symbol.

- **Adding a module is a two-place edit.** A new `src/foo.cyr` must be added to
  **both** `src/lib.cyr` (an `include "src/foo.cyr"` line, after its dependencies)
  **and** `cyrius.cyml [lib].modules` (in the same dependency order). Miss either
  and the bundle drifts from the build.

- **Order matters.** `error.cyr` is dep-free; `format.cyr` builds on it; `sign.cyr`
  and `fileio.cyr` build on `format.cyr`; `dtype.cyr` uses `format.cyr` accessors.
  Reordering `[lib].modules` without re-running `make dist` breaks the bundle.

- **`lib/` is a build artifact.** It is populated by `cyrius deps` from
  `[deps].stdlib` + `[deps.sigil]`, is gitignored, and must never be a symlink to
  a cyrius checkout (that causes cross-repo writes). The `check-lib-wiring` make
  target guards this.

## The rule

Never add a stdlib `include` to a domain module. Never reorder `[lib].modules`
without `make dist`. Trust the build over the LSP.
