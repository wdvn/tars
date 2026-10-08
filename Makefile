# tars — Go 1.24 build wrapper
# Requires: Go 1.24+, sqlite3 CLI (for memory/init.sh)

GO ?= go
BIN_DIR ?= bin
TARGET ?= $(BIN_DIR)/tars

.PHONY: build run test init-db clean help

# Default target
build:
	@mkdir -p $(BIN_DIR)
	$(GO) build -o $(TARGET) ./cmd/tars

run: build
	$(TARGET) $(ARGS)

test:
	$(GO) test -v ./...

init-db:
	bash memory/init.sh

clean:
	rm -rf $(BIN_DIR)

help:
	@echo "tars Makefile targets:"
	@echo "  make build     — compile (go build -o bin/tars ./cmd/tars)"
	@echo "  make run       — build and run demo (ARGS='chat' for REPL)"
	@echo "  make test      — run unit tests (go test -v ./...)"
	@echo "  make init-db   — initialize .tars/tars.db"
	@echo "  make clean     — remove bin/"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make test"
	@echo "  make run ARGS=chat"
	@echo "  bin/tars report"
