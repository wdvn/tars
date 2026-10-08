# tars

> *"TARS, what's your honesty parameter?"* — Cooper, *Interstellar*

Like T.A.R.S. in *Interstellar* — a tactical partner: honest, pragmatic, ready to do what is necessary.

**Status:** early-stage skeleton + runtime demo. The default command runs an **automated showcase**, not an interactive agent loop like [mini-agent](https://github.com/wdvn/mini).

---

## Choose language / Chọn ngôn ngữ

| | |
|---|---|
| 🇬🇧 **[English](docs/en/README.md)** | Architecture, parameters, behavior, problem-solving |
| 🇻🇳 **[Tiếng Việt](docs/vi/README.md)** | Kiến trúc, tham số, hành vi, xử lý vấn đề |

---

## Build & run

Requires [Go](https://go.dev/) 1.24+ and `sqlite3` CLI.

```bash
cp .env.example .env          # optional: Ollama / cloud LLM settings
make init-db                  # create .tars/tars.db
make build                    # build ./bin/tars
```

### Run modes

| Command | Purpose |
|---------|---------|
| `./bin/tars` | **Runtime demo** — streaming, perception, recall, session, autonomous loop, metrics. Uses a **hardcoded mission and plan**; does **not** wait for operator input. |
| `./bin/tars chat` | **Interactive REPL** — read a line from stdin, stream an LLM reply, persist session + recall. **Chat only** — does not run Executor tools or the tri-agent loop. |
| `./bin/tars report` | Read metrics from SQLite (human or `--json`). |
| `./bin/tars embed pull` | Pull the embedding model via Ollama (`TARS_EMBED_*`). |

```bash
./bin/tars                    # automated tri-agent demo (default)
./bin/tars chat               # operator chat (no autonomous execution)
./bin/tars report             # metrics query
```

**Why doesn't `./bin/tars` wait for chat like mini-agent?**

tars follows a **tri-agent** design (Analyst · Executor · Monitor) with ORIENT → ASSESS → PLAN → ACT → VERIFY. The LLM lives in Analyst **reasoning blocks** and outputs structured JSON — it is not the center of a single tool loop. The default CLI entry point is a **capability demo**, not the operator-facing product surface. For day-to-day “type a request → agent runs tools”, use `./bin/tars chat` for conversation today, or see [tars vs. mini-agent](docs/en/comparison.md) for the full comparison.

---

## Configuration

Copy `.env.example` to `.env`. Shell environment variables override file values.

| Variable | Default | Role |
|----------|---------|------|
| `TARS_LLM_MODEL` | `qwen2.5:0.5b` | Ollama chat model |
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama server |
| `TARS_LLM_AUTO_PULL` | `1` | Auto-pull missing LLM model |
| `TARS_LLM_PROVIDER` | *(Ollama)* | Force `ollama` · `openai` · `anthropic` · `stub` |
| `TARS_SYSTEM_FILE` | — | Custom system prompt (`.md` file) |
| `TARS_MAX_TOKENS` | `8192` | Max completion tokens |
| `TARS_EMBED_*` | see `.env.example` | Semantic recall via Ollama embeddings |

**Stub provider** (offline, no Ollama):

```bash
TARS_LLM_PROVIDER=stub ./bin/tars
```

**Cloud** — set `OPENAI_COMPAT_*` or `ANTHROPIC_API_KEY` and `TARS_LLM_PROVIDER=openai|anthropic`. Details in `.env.example`.

---

## Optional: sqlite-vector

```bash
TARS_VECTOR_EXT=/path/to/vector.so bash memory/init.sh
```

---

## Documentation

| Topic | Link |
|-------|------|
| Architecture (tri-agent, cognitive loop) | [EN](docs/en/architecture.md) · [VI](docs/vi/architecture.md) |
| tars vs. mini-agent | [EN](docs/en/comparison.md) · [VI](docs/vi/comparison.md) |
| Behavior & parameters | [docs/en/README.md](docs/en/README.md) |
