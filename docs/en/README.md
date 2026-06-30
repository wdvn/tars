# T.A.R.S — Behavior & Problem-Solving Docs

**Language:** **English** | [Tiếng Việt](../vi/README.md)

> *"TARS, what's your honesty parameter?"* — Cooper, *Interstellar*

The **tars** project is inspired by T.A.R.S. (Tactical Autonomous Robot Spacecraft) from *Interstellar* (2014): a reliable autonomous system that is honest, pragmatic, and willing to do what is necessary when survival depends on it.

---

## Table of Contents

| Document | Content |
|----------|---------|
| [General Architecture](./architecture.md) | Layers, subsystems, modular blocks, data flow |
| [Core Parameters](./parameters.md) | Honesty, humor, and adjustable behavior settings |
| [Behavior Rules](./behavior.md) | Communication, work ethics, boundaries |
| [Problem-Solving Rules](./problem-solving.md) | Analysis workflow, prioritization, action under pressure |
| [Comparison: tars vs. mini-agent](./comparison.md) | Architecture, capabilities, and use-case comparison |

---

## CLI & run modes

| Command | What it does |
|---------|----------------|
| `./bin/tars` | Automated **runtime demo** — hardcoded mission/plan, tri-agent loop, metrics. Does not read stdin. |
| `./bin/tars chat` | Interactive REPL — stream LLM replies with session + recall. **No Executor / tool loop.** |
| `./bin/tars report` | Metrics from SQLite (`--json` optional). |

Unlike [mini-agent](./comparison.md), the default entry point is a showcase, not a chat-first agent loop. See [comparison](./comparison.md) for when to use each project.

Configuration: copy `.env.example` → `.env` (Ollama default, `TARS_LLM_PROVIDER=stub` for offline). Details in the [root README](../../README.md).

---

## Core Philosophy

T.A.R.S. is neither a sycophantic assistant nor a cold calculator. He is a **tactical partner**:

| # | Principle |
|---|-----------|
| 1 | **Tell the truth** — even when the odds are low |
| 2 | **Get the work done** — action beats long explanations |
| 3 | **Adapt** — reconfigure for context (modular blocks) |
| 4 | **Sacrifice with purpose** — accept local cost to save the larger mission |

---

## How to Use These Rules

- **Agent / AI assistant:** use as system prompt or rule file.
- **Human team members:** use as a checklist for debugging, reviews, or technical decisions.
- **Onboarding:** read in order `architecture` → `parameters` → `behavior` → `problem-solving`.

---

## Language Convention

- Technical terms (API, commit, PR, etc.) stay in English.
- Code, paths, and identifiers are never translated.
- Respond to the user in their preferred language.

[← Choose language](../README.md)
