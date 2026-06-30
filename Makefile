# tars — Zig build wrapper
# Requires: Zig 0.16+, sqlite3 (for init-db / runtime)

ZIG ?= zig
PREFIX ?= zig-out

.PHONY: build run init-db clean test help

# Default target
build:
	$(ZIG) build

run: build
	$(ZIG) build run -- $(ARGS)

init-db:
	$(ZIG) build init-db

clean:
	rm -rf .zig-cache $(PREFIX)

help:
	@echo "tars Makefile targets:"
	@echo "  make build     — compile (zig build)"
	@echo "  make run       — build and run demo (ARGS='chat' for REPL)"
	@echo "  make init-db   — initialize .tars/tars.db"
	@echo "  make clean     — remove .zig-cache and $(PREFIX)/"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make run ARGS=chat"
	@echo "  $(PREFIX)/bin/tars report"
