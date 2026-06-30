# T.A.R.S. vs. mini-agent — Comparison

**Language:** **English** | [Tiếng Việt](../vi/comparison.md)

A comparison between **tars** (this project) and **[mini-agent](https://github.com/wdvn/mini)** — both are AI agents written in Zig, but follow two different philosophies.

[← Index](./README.md) · [Architecture](./architecture.md) · [Parameters](./parameters.md) · [Behavior](./behavior.md) · [Problem-Solving](./problem-solving.md)

---

## 1. Overview

| | **tars** | **mini-agent** (`wdvn/mini`) |
|---|----------|------------------------------|
| **Goal** | Architecture-driven tactical autonomous agent, inspired by T.A.R.S. in *Interstellar* | Small, pragmatic terminal AI agent, ready to use |
| **Philosophy** | Design-led: architecture, safety, auditability | Minimal, dependency-free, single runnable binary |
| **Language** | Zig 0.16+ | Zig 0.16.0 (upgraded from 0.15.2) |
| **Size** | ~4.4k lines of Zig | ~4.5k lines of Zig |
| **Status** | Skeleton + runtime demo (early stage) | Complete 1.0.0 release, ~12MB binary |
| **License** | (see `LICENSE`) | MIT |

---

## 2. Architecture

| Aspect | **tars** | **mini-agent** |
|--------|----------|----------------|
| **Agent model** | **Tri-agent**: Analyst (reasoning) · Executor (action) · Monitor (watch) | **Single agentic loop** (`AgentLoop`) |
| **Cognitive loop** | ORIENT → ASSESS → PLAN → ACT → VERIFY with loop-back | Simple tool loop (max 20 iterations) |
| **Layering** | 5 layers L0–L4 (Infra · Tri-Agent · Cognitive · Policy · Operator) | Flat: main → agent → backend/tools |
| **Orchestration** | Mission Controller + agent event bus | Directly in `agent.zig` |
| **LLM placement** | Embedded in Analyst's Reasoning blocks (not an orchestrator) | Center of the loop, decides tool calls |

---

## 3. Capabilities

| Aspect | **tars** | **mini-agent** |
|--------|----------|----------------|
| **LLM backends** | Anthropic, OpenAI | OpenAI-compatible, Anthropic Claude, Ollama (local) |
| **Streaming** | Yes (`stream/`) | Yes (SSE / NDJSON) |
| **Memory** | SQLite + sqlite-vector: episodic memory, semantic recall, missions, audit log | In-memory history with auto-compacting |
| **Tools** | Executor action blocks: shell, file_editor, git_ops, mcp_bridge; perception: file_reader, grep | 9 built-in: bash, file_read/write/edit, glob, grep, http_request, web_search, skills |
| **MCP** | Yes (`mcp/client`) | Yes (JSON-RPC over stdio, `server__tool` prefix) |
| **Safety** | Safety Guard (P5 hard boundaries) + Monitor verify (test/lint/diff) | bash blocklist patterns + tool allow/blocklist + blocks writes to `/etc /sys /proc /dev` |
| **Metrics / observability** | Dedicated `metrics` module (collector, registry, persist, report) + audit log | None dedicated |
| **Auditability** | Append-only `audit_log` written by Monitor | None |

---

## 4. Interface & operation

| Aspect | **tars** | **mini-agent** |
|--------|----------|----------------|
| **Run modes** | `chat` (REPL), `report`, runtime demo | Interactive REPL + single-shot (`-e`) |
| **Slash commands** | Not yet | `/help`, `/clear`, `/model`, `/quit` |
| **Runtime backend switch** | Via environment variables | `/model <backend> <model>` live in REPL |
| **Configuration** | Env (`TARS_VECTOR_EXT`, `TARS_MCP_CMD`) | Auto-load `.env` (CWD, `~/.mini/.env`), many env vars |
| **System prompt** | In-code reasoning blocks | Custom `.md` file (`MINI_SYSTEM_FILE`) |
| **Distribution** | `zig build` | Single binary, cross-compile, install to PATH |
| **Bundled example** | Internal demo | Newspaper agent (HN + arXiv digest) |

---

## 5. Documentation

| Aspect | **tars** | **mini-agent** |
|--------|----------|----------------|
| **Format** | Bilingual docs (EN/VI): architecture, parameters, behavior, problem-solving | Detailed README + `docs/plan.md` |
| **Focus** | Design, philosophy, inter-agent contracts | Usage, configuration, tools, contributing |

---

## 6. Bottom line

| Choose... | When you need... |
|-----------|------------------|
| **tars** | A structured agent framework with clear role separation, strong safety and auditing — suited for long-term, design-intentional builds |
| **mini-agent** | A lightweight terminal agent that runs immediately, multi-backend, many built-in tools — suited for daily use and quick automation |

In short: **tars** leans toward *architecture and principles* (tri-agent, semantic memory, safety, metrics), while **mini-agent** leans toward *pragmatism and readiness* (single binary, multi-backend, 9 tools, real examples).

[← Index](./README.md)
