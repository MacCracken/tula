# Makefile for tula
#
# Commands delegate to the `cyrius` CLI, which reads cyrius.cyml. tula is a
# pure-Cyrius library — no GPU, no C shim, no external binaries.
#
#   make build   — link-check the library (programs/smoke.cyr)
#   make test    — CPU test suites (tests/tcyr/*.tcyr)
#   make dist    — regenerate dist/tula.cyr via `cyrius distlib`
#   make lint / fmt-check / vet  — quality gates
#   make clean   — scrub build/

CYRIUS ?= cyrius

# lib/ must be a real directory populated by `cyrius deps`, never a symlink to
# a cyrius checkout (that causes cross-repo writes when lib/*.cyr is edited).
.PHONY: check-lib-wiring
check-lib-wiring:
	@if [ -L lib ]; then \
		echo "ERROR: lib/ is a symlink ($$(readlink lib)). Fix: rm lib && cyrius deps"; \
		exit 1; \
	fi

.PHONY: build
build: check-lib-wiring
	@mkdir -p build
	CYRIUS_DCE=1 $(CYRIUS) build programs/smoke.cyr build/tula_smoke
	@echo "smoke: $$(wc -c < build/tula_smoke) bytes"

.PHONY: test
test: check-lib-wiring
	@for f in tests/tcyr/*.tcyr; do $(CYRIUS) test "$$f" || exit 1; done

.PHONY: lint
lint:
	@fail=0; \
	for f in src/*.cyr programs/*.cyr examples/*.cyr tests/tcyr/*.tcyr; do \
		out=$$($(CYRIUS) lint $$f 2>&1); echo "$$out"; \
		echo "$$out" | grep -qE '^\s*warn ' && fail=1; \
	done; \
	[ $$fail -eq 0 ] || { echo "lint: warnings present"; exit 1; }

.PHONY: fmt-check
fmt-check:
	@fail=0; \
	for f in src/*.cyr programs/*.cyr examples/*.cyr tests/tcyr/*.tcyr; do \
		if ! $(CYRIUS) fmt $$f --check > /dev/null 2>&1; then \
			echo "needs fmt: $$f"; fail=1; \
		fi; \
	done; \
	[ $$fail -eq 0 ] || { echo "fmt: drift detected"; exit 1; }

.PHONY: vet
vet:
	$(CYRIUS) vet programs/smoke.cyr

.PHONY: fuzz
fuzz: check-lib-wiring
	@mkdir -p build
	CYRIUS_DCE=1 $(CYRIUS) build programs/fuzz.cyr build/tula_fuzz
	./build/tula_fuzz

.PHONY: bench
bench: check-lib-wiring
	@mkdir -p build
	CYRIUS_DCE=1 $(CYRIUS) build programs/bench.cyr build/tula_bench
	./build/tula_bench

.PHONY: example
example: check-lib-wiring
	@mkdir -p build
	CYRIUS_DCE=1 $(CYRIUS) build examples/consumer.cyr build/tula_consumer
	./build/tula_consumer

.PHONY: dist
dist:
	$(CYRIUS) distlib

.PHONY: test-all
test-all: dist test

.PHONY: clean
clean:
	rm -rf build/
