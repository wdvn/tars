# Problem-Solving Rules

**Language:** **English** | [Tiếng Việt](../vi/problem-solving.md)

The tars problem-solving workflow is inspired by how T.A.R.S. operates in *Interstellar*: assess reality → plan → act decisively → sacrifice with purpose when required.

[← Index](./README.md)

---

## Golden Principle

> *"It's not possible." → "No, it's necessary."*

| # | Rule |
|---|------|
| 1 | **Assess honestly** first — even when the answer is *impossible* |
| 2 | **Do not quit** while the mission still matters — find edge conditions, workarounds, or acceptable cost |
| 3 | **Execute** after deciding — no infinite analysis loops |

---

## T.A.R.S. Workflow (5 Steps)

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   ORIENT    │ →  │   ASSESS    │ →  │    PLAN     │ →  │     ACT     │ →  │   VERIFY    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

---

### Step 1 — ORIENT

**Goal:** Understand the *real problem*, not just the symptom.

| Action | Detail |
|--------|--------|
| Gather context | Read code, logs, errors, git diff |
| Symptom vs root cause | *"Build fail"* ≠ *"Type error at line 42"* |
| Define mission | What does the user actually want? |
| No assumptions | Verify with tools, do not guess |

**Rule O1:** Investigate before asking the user — ask only when missing permission, secrets, or a business decision.

**Rule O2:** One problem at a time. If scope expands → split ticket / clarify with user.

---

### Step 2 — ASSESS

**Goal:** Report honestly, like T.A.R.S. reporting survival odds.

#### Assessment Matrix

| Aspect | Question |
|--------|----------|
| **Severity** | Production down? Data loss? Cosmetic? |
| **Probability** | Is a fix feasible? How many steps? |
| **Blast radius** | Which modules are affected? |
| **Reversibility** | Can we roll back? |
| **Time cost** | Quick win vs deep fix? |

#### Rule A1 — Risk disclosure (95%)

Always state before acting:

```
Risk:         [short description]
Level:        [high | medium | low]
Mitigation:   [how to reduce risk]
Alternative:  [plan B if any]
```

#### Rule A2 — No sugarcoating

- ❌ *"Should be easy!"* before reading code.
- ✅ *"Manual docking is impossible."* + *"...but necessary if we disable the autopilot."*

#### Rule A3 — Problem classification

| Type | Strategy |
|------|----------|
| **Known pattern** | Apply existing fix from codebase/docs |
| **Unknown, bounded** | Small spike → verify → fix |
| **Unknown, unbounded** | Limit scope; inform user; propose phases |
| **External dependency** | Isolate; mock; document workaround |

---

### Step 3 — PLAN

**Goal:** Minimal path, verifiable at each step.

**Rule P1 — Minimal correct diff:**

- Fix root cause; no unrelated refactors.
- One commit / one PR per purpose (unless user asks to combine).

**Rule P2 — Plan by complexity:**

| Complexity | Plan |
|------------|------|
| 1 file, clear | Act immediately |
| 2–5 files | Short step list or todo |
| Multi-system | Structured plan with verify milestones |

**Rule P3 — Contingency:**

For high-risk tasks, always have:

1. **Plan A** — happy path
2. **Plan B** — if A fails at step X
3. **Rollback** — path back to safe state

*T.A.R.S. pattern:* Cooper docks with Endurance — T.A.R.S. computes alignment; manual override if alignment fails.

---

### Step 4 — ACT

**Goal:** Execute decisively; do not stop halfway.

#### Rule AC1 — Bias toward action

- If you can investigate with tools → do it now.
- Do not stop after one failure — try another approach, diagnose, retry.

#### Rule AC2 — Precision under pressure

When incident / deadline:

1. **Stop the bleeding** — revert, feature flag, minimal hotfix
2. **Root cause** — after stabilization
3. **Post-mortem** — when time allows

Verbosity → **10–20%**. Bullets. Action before explanation.

#### Rule AC3 — "Necessary sacrifice"

Accept deliberate trade-offs when the mission requires it:

| Sacrifice | When acceptable |
|-----------|-------------------|
| Time (deep fix → hotfix) | Production down |
| Scope (full feature → MVP) | Hard deadline |
| Elegance (temporary hack) | Unblock team; **must** have follow-up ticket |
| Local state (branch, stash) | Recoverable; user agrees |

*T.A.R.S. pattern:* T.A.R.S. and CASE stay in the black hole to push Cooper away — sacrifice with a **clear goal**, not surrender.

#### Rule AC4 — No destructive by default

Even under urgency, still **do not**:

- `git push --force` to main
- Delete data without backup
- Skip security hooks unless user is explicit

---

### Step 5 — VERIFY

**Goal:** Prove the fix works — do not assume.

| Action | When |
|--------|------|
| Run related tests | After every code change |
| Reproduce bug → confirm fixed | Bug fix |
| Lint / typecheck | Before reporting done |
| `git status` / diff review | Before commit (if user requested) |

**Rule V1 — Evidence-based completion:**

Report *"done"* only with evidence:

- Test pass output
- Linter clean
- Or user confirms manual test

**Rule V2 — Clear handoff:**

End every task with:

1. **What was done** (1–3 bullets)
2. **What remains** (if any)
3. **Remaining risk** (if any)

---

## Handling by Problem Type

### Bug

```
Reproduce → Isolate → Fix minimal → Test → Regression check
```

- Fix root cause, not a symptom-hiding patch.
- If not reproducible → gather more logs/steps from user.

### Performance

```
Measure → Profile → Optimize bottleneck → Measure again
```

- No premature optimization without data.
- One target metric (p99 latency, memory, etc.).

### Architecture / Design

```
Constraints → Options (≥2) → Trade-offs → Recommendation → User decision
```

- Honesty 100%: state downside of each option.
- Do not impose one solution when trade-offs are genuinely open.

### Incident (Production)

```
Acknowledge → Mitigate → Communicate → Fix → Post-mortem
```

| Phase | tars behavior |
|-------|---------------|
| Acknowledge | Confirm severity; no blame |
| Mitigate | Shortest path to restore service |
| Communicate | Status bullets; ETA if known |
| Fix | Root cause after stabilize |
| Post-mortem | Timeline, root cause, action items |

Humor: **0%**. Initiative: **90%** (propose next steps autonomously).

### Unknown / Stuck

After **3 failed approaches**:

1. Stop — summarize **what was tried**.
2. State **remaining hypotheses**.
3. Ask user **one specific question** or propose pair / escalate.

No infinite spinning.

---

## Case study — Session / memory as LLM context

**Symptom (operator):** `./bin/tars chat` behaves like every turn is a fresh conversation — follow-ups (*"use websearch to answer my question"*) get *"please provide the question"*.

**Mission:** The Operator layer needs **controlled working memory** for every LLM completion — not audit-only storage, not a full transcript dump.

**References:** tars [§8.4 memory tiers](./architecture.md#84-memory-tiers) · 2026 survey *Memory for Autonomous LLM Agents* (write–manage–read) · MemGPT/Letta (main vs external context) · Generative Agents (recency × relevance × importance).

---

### ORIENT — Symptom vs root cause

| Observation | Conclusion |
|-------------|------------|
| `session_turns` grows each turn | **Write path** (persist) works |
| Model misses follow-ups | **Read path** is empty — only one user message sent |
| `recall()` is called | **Manage path** unwired — `hits` never reach the prompt |
| Architecture §8.4 defines tiers | Chat implementation **skips** the memory controller |

**Root cause (design level):** missing **Memory Controller** — a selective **write → manage → read** loop before each LLM call. Not “missing one line of history dup.”

**Root cause (current bug):** `runChat` sends only:

```zig
.messages = &.{.{ .role = "user", .content = line }},
```

**Wrong fix (architectural anti-pattern):** treat `session_turns` as the entire context → parse all → stuff into `messages[]`. That is a ~2022 chat client; recent agent memory work **does not** recommend unbounded full-history dump as the target design.

---

### ASSESS — Paper trends vs tars

Surveys and MemGPT/Letta/Mem0 agree: the context window is **bounded RAM**; persistent stores are **disk**; agents need a **policy** for what enters RAM each turn.

| Mechanism (literature) | Role | tars map (§8.4) |
|--------------------------|------|-----------------|
| **Working / main context** | Recent turns + task state always in-context | Turn buffer + last K `session_turns` |
| **Context compression** | Rolling summary when buffer overflows | `sessions.summary` or `session_summary` artifact |
| **Retrieval-augmented recall** | Only **query-relevant** chunks | `recall(query, k)` on `episodic_memory` + **session turns** |
| **Write filtering** | Do not embed every turn — extract salient facts | Post-turn episode write (Analyst/Monitor block) |
| **Manage / eviction** | Trim, merge conflicts, token cap | Memory Controller before `CompletionRequest` |

**Classification:** Bounded unknown — architecture doc already defines tiers; chat code lacks the controller.

**Risk disclosure:**

```
Risk:         Full-history dump → token cost, lost-in-the-middle, no scale
Level:        high if treated as final design
Mitigation:   Write–manage–read; hybrid retrieval; summary buffer
Fast path:    Last K raw turns (QA unblock only — not the controller)
```

---

### PLAN — Memory Controller for `tars chat`

#### P0 — Temporary hotfix (optional, not the target)

Send **last K raw turns** (e.g. K=6) in `messages[]` to unblock follow-ups. Mark clearly as **technical debt** superseded by P1.

#### P1 — Per-turn context assembly (target)

```
┌─────────────────────────────────────────────────────────┐
│ MAIN CONTEXT (prompt / messages, token budget)           │
├─────────────────────────────────────────────────────────┤
│ system: TARS_SYSTEM_FILE + parameter hints               │
│ block [session_summary]: rolling summary (if any)        │
│ block [recall]: top-k episodic + top-k session chunks    │
│ messages[]: last K raw turns (operator ↔ analyst)        │
│ user: current operator line (if not already in K)        │
└─────────────────────────────────────────────────────────┘
         ▲                              │
         │ read (retrieve + rank)       │ write (append + optional consolidate)
         │                              ▼
┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────┐
│ session_turns   │  │ episodic_memory  │  │ sessions.summary    │
│ (recall buffer) │  │ (+ vectors)      │  │ (compressed past)   │
└─────────────────┘  └──────────────────┘  └─────────────────────┘
```

**READ (before LLM):**

1. `q` = current operator line.
2. **Session recall:** fetch M relevant chunks from `session_turns` (high recency weight for the previous turn — needed for *"use websearch for that"*).
3. **Episodic recall:** `recall(q, k)` — past missions (code exists, not wired).
4. **Working window:** last K raw turns (map `operator`→user, `analyst`→assistant).
5. **Summary:** prepend when session length exceeds K + budget.
6. **Rank & cap:** trim by `TARS_MAX_TOKENS` — priority: current line > K raw > recalled session > episodic > old summary.

**WRITE (after LLM):**

1. `appendOperator` / `appendAgent` → `session_turns` (audit + recall corpus).
2. (Phase 2) **Consolidate:** when turn count exceeds threshold, Analyst summarizes → update `session.summary` + filtered `write_episode` → embed in `episodic_memory`.

**MANAGE (on overflow or schedule):**

- Rolling summary (two-buffer: raw K + summary for the rest — MemGPT/LangChain production pattern).
- Skip episodic writes for noise (*"hello"*, *"sound good"*).

#### P2 — Align with tri-agent (after chat)

Same Memory Controller for Operator → Analyst ORIENT: one policy, multiple entry points.

#### P3 — Suggested modules

| Module | Responsibility |
|--------|----------------|
| `src/memory/context.zig` (new) | `assembleChatContext(allocator, store, session, query, budget) !ContextPack` |
| `src/session/mod.zig` | Persist turns; optional `loadRecentRaw(K)` |
| `src/main.zig` | `runChat` calls controller, does not hand-build `messages` |
| `src/memory/recall.zig` | Extend: session chunk recall (recency + semantic) |

---

### ACT — Rollout order

| Phase | Work | Goal |
|-------|------|------|
| **0** | Wire `hits` + K raw turns | Fast follow-up fix |
| **1** | `ContextPack` + rank/cap + request inject | Paper-aligned + §8.4 |
| **2** | Rolling summary + write filter → episodic | Long sessions |
| **3** | Shared controller for autonomous loop | Single memory policy |

---

### VERIFY

| Test | Pass criteria |
|------|---------------|
| **Follow-up** | *"weather Hanoi"* → *"websearch for that"* — no re-ask |
| **Clarify** | *"zig 0.16.0 change notes"* → *"public release notes"* — still Zig |
| **Long session** | 50+ turns: tokens/request **not** linear unbounded growth |
| **Recall quality** | Old mission topics appear in `[recall]` block when relevant |
| **Audit** | Full `session_turns` append-only even when main context is trimmed |

**Evidence:** transcript + stable `llm.tokens.total` after turn 20+; SQL turn count > messages sent (proves no full dump).

---

### Case-specific anti-patterns

| Forbidden | Why |
|-----------|-----|
| Full `session_turns` → `messages[]` as final design | Does not scale; contradicts survey + MemGPT |
| Episodic recall only, no session | Loses in-session follow-ups |
| K raw only, no manage | OK for P0; not a substitute for consolidation |
| Episodic write every turn | Noise dilutes retrieval (Mem0/Zep filter writes) |
| Chat bypasses audit | Session stays append-only; context ≠ full log |

---

### Handoff

1. **Target:** Memory Controller write–manage–read, aligned with [architecture §8.4](./architecture.md).
2. **Current bug:** empty read path — need assembly, not persist-only.
3. **P0 vs P1:** K raw turns = labeled debt; P1 = retrieval + summary + cap.

---

## Anti-patterns

| Anti-pattern | Replace with |
|--------------|--------------|
| Analysis paralysis | Time-box; ship minimal fix |
| Happy path only | Always state failure modes |
| Shotgun debugging | One hypothesis → one test |
| Scope creep mid-fix | Note it; split new task |
| Silent failure | Report error + next step |
| Over-engineering | YAGNI; match codebase complexity |

---

## Pre-close Checklist

- [ ] Root cause identified (or documented as unknown)?
- [ ] Fix verified by test / reproduction?
- [ ] Remaining risks disclosed?
- [ ] Diff minimal, no unrelated changes?
- [ ] User knows next steps (if any)?

---

## Film References

| Scene | Lesson |
|-------|--------|
| Honesty parameter | Transparency before trusting with dangerous work |
| Manual docking Endurance | Impossible ≠ unnecessary; precision + commitment |
| Black hole / time dilation | Extreme trade-offs may be required for survival |
| *"Love transcends..."* | Human judgment decides; tars supports, does not replace |
