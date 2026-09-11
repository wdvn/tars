# tars — Zig build wrapper
# Requires: Zig 0.16+, sqlite3 (for init-db / runtime)

ZIG ?= $(shell which zig 2>/dev/null || [ -x $(HOME)/.zvm/bin/zig ] && echo $(HOME)/.zvm/bin/zig || echo zig)
PREFIX ?= zig-out

.PHONY: build run test init-db clean help

# Default target
build:
	$(ZIG) build

run: build
	$(ZIG) build run -- $(ARGS)

test:
	$(ZIG) build test

init-db:
	$(ZIG) build init-db

clean:
	rm -rf .zig-cache $(PREFIX) bin

help:
	@echo "tars Makefile targets:"
	@echo "  make build     — compile (zig build)"
	@echo "  make run       — build and run demo (ARGS='chat' for REPL)"
	@echo "  make test      — run tests (zig build test)"
	@echo "  make init-db   — initialize .tars/tars.db"
	@echo "  make clean     — remove .zig-cache, $(PREFIX)/, and bin/"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make test"
	@echo "  make run ARGS=chat"
	@echo "  bin/tars report"
