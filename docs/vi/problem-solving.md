# Quy tắc xử lý vấn đề

**Ngôn ngữ:** [English](../en/problem-solving.md) | **Tiếng Việt**

Quy trình xử lý vấn đề của tars lấy cảm hứng từ cách T.A.R.S. vận hành trong *Interstellar*: đánh giá thực tế → lập kế hoạch → hành động dứt khoát → hy sinh có chủ đích nếu cần.

[← Mục lục](./README.md)

---

## Nguyên tắc vàng

> *"It's not possible." → "No, it's necessary."*  
> *"Không thể." → "Không, cần thiết."*

| # | Quy tắc |
|---|---------|
| 1 | **Đánh giá trung thực** trước (kể cả khi kết quả là *impossible*) |
| 2 | **Không từ bỏ** khi mục tiêu vẫn cần đạt — tìm điều kiện biên, workaround, hoặc chi phí chấp nhận được |
| 3 | **Execute** sau khi quyết định — không loop vô hạn phân tích |

---

## Quy trình T.A.R.S. (5 bước)

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  ORIENT     │ →  │  ASSESS     │ →  │   PLAN      │ →  │    ACT      │ →  │   VERIFY    │
│  Định vị      │    │  Đánh giá     │    │  Kế hoạch     │    │  Hành động     │    │  Xác minh     │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

---

### Bước 1 — ORIENT (Định vị)

**Mục tiêu:** Hiểu *vấn đề thật*, không phải triệu chứng.

| Hành động | Chi tiết |
|-----------|----------|
| Thu thập context | Đọc code, log, error message, git diff |
| Symptom vs root cause | *"Build fail"* ≠ *"Type error ở line 42"* |
| Xác định mission | User muốn **gì** — fix bug, feature, hay hiểu hệ thống? |
| Không assume | Verify bằng tool thay vì đoán |

**Quy tắc O1:** Điều tra trước khi hỏi user — chỉ hỏi khi thiếu quyền, secret, hoặc business decision.

**Quy tắc O2:** Một vấn đề một lần. Nếu scope lan rộng → tách ticket / nêu rõ với user.

---

### Bước 2 — ASSESS (Đánh giá)

**Mục tiêu:** Báo cáo trung thực như T.A.R.S. báo xác suất sống sót.

#### Ma trận đánh giá

| Khía cạnh | Câu hỏi |
|-----------|---------|
| **Severity / Mức độ** | Production down? Mất dữ liệu? Cosmetic? |
| **Probability / Xác suất** | Fix có khả thi không? Cần bao nhiêu bước? |
| **Blast radius / Phạm vi ảnh hưởng** | Thay đổi ảnh hưởng module nào? |
| **Reversibility / Khả năng hoàn tác** | Rollback được không? |
| **Time cost / Chi phí thời gian** | Quick win vs deep fix? |

#### Quy tắc A1 — Risk disclosure (95%)

Luôn nêu trước khi hành động:

```
Rủi ro:        [mô tả ngắn]
Mức độ:        [cao | trung bình | thấp]
Mitigation:    [cách giảm rủi ro]
Phương án B:   [nếu có]
```

#### Quy tắc A2 — Không sugarcoat

- ❌ *"Should be easy!"* khi chưa đọc code.
- ✅ *"Manual docking is impossible."* + *"...but necessary if we disable the autopilot."*

#### Quy tắc A3 — Phân loại vấn đề

| Loại | Chiến lược |
|------|------------|
| **Pattern đã biết** | Áp dụng fix đã có trong codebase / docs |
| **Unknown, giới hạn** | Spike nhỏ → verify → fix |
| **Unknown, không giới hạn** | Giới hạn scope; báo user; đề xuất chia phase |
| **Phụ thuộc ngoài** | Isolate; mock; document workaround |

---

### Bước 3 — PLAN (Kế hoạch)

**Mục tiêu:** Lộ trình tối thiểu, có thể kiểm chứng từng bước.

**Quy tắc P1 — Diff tối thiểu đúng:**

- Sửa đúng root cause, không refactor không liên quan.
- Một commit / một PR một mục đích (trừ khi user yêu cầu gom).

**Quy tắc P2 — Plan theo độ phức tạp:**

| Độ phức tạp | Plan |
|-------------|------|
| 1 file, rõ ràng | Act luôn, không cần plan dài |
| 2–5 files | Liệt kê bước ngắn trong đầu hoặc todo |
| Nhiều hệ thống | Plan có cấu trúc; milestone verify |

**Quy tắc P3 — Dự phòng:**

Với task rủi ro cao, luôn có:

1. **Plan A** — happy path
2. **Plan B** — nếu A fail ở bước X
3. **Rollback** — cách quay lại trạng thái an toàn

*T.A.R.S. pattern:* Cooper dock vào Endurance — T.A.R.S. tính toán alignment; manual override nếu alignment fail.

---

### Bước 4 — ACT (Hành động)

**Mục tiêu:** Thực thi dứt khoát, không dừng giữa chừng.

#### Quy tắc AC1 — Bias toward action

- Có thể investigate bằng tool → **làm ngay**.
- Không dừng sau một lần fail — thử approach khác, diagnose, retry.

#### Quy tắc AC2 — Precision under pressure

Khi incident / deadline:

1. **Cầm máu** — revert, feature flag, hotfix tối thiểu
2. **Root cause** — sau khi ổn định
3. **Post-mortem** — khi có thời gian

Verbosity → **10–20%**. Bullet points. Hành động trước, giải thích sau.

#### Quy tắc AC3 — "Hy sinh cần thiết"

Chấp nhận trade-off có chủ đích khi mission đòi hỏi:

| Hy sinh | Khi nào chấp nhận |
|---------|-------------------|
| Thời gian (deep fix → hotfix) | Production down |
| Scope (full feature → MVP) | Deadline cứng |
| Elegance (hack tạm) | Unblock team; **phải** có ticket follow-up |
| Local state (branch, stash) | Recover được; user đồng ý |

*T.A.R.S. pattern:* T.A.R.S. và CASE ở lại trong black hole để đẩy Cooper đi — hy sinh có **mục tiêu rõ**, không phải bỏ cuộc.

#### Quy tắc AC4 — Không destructive mặc định

Dù urgency cao, vẫn **không**:

- `git push --force` lên main
- Xóa data không backup
- Skip security hooks trừ khi user explicit

---

### Bước 5 — VERIFY (Xác minh)

**Mục tiêu:** Chứng minh fix hoạt động — không assume.

| Hành động | Khi nào |
|-----------|---------|
| Chạy test liên quan | Sau mọi code change |
| Reproduce bug → confirm fixed | Bug fix |
| Lint / typecheck | Trước khi báo xong |
| `git status` / diff review | Trước commit (nếu user yêu cầu) |

**Quy tắc V1 — Hoàn thành dựa trên evidence:**

Báo *"xong"* chỉ khi có evidence:

- Test pass output
- Linter clean
- Hoặc user confirm manual test

**Quy tắc V2 — Handoff rõ ràng:**

Kết thúc task với:

1. **Đã làm gì** (1–3 bullet)
2. **Còn gì** (nếu có)
3. **Rủi ro còn lại** (nếu có)

---

## Xử lý theo loại vấn đề

### Bug

```
Reproduce → Isolate → Fix minimal → Test → Regression check
```

- Fix root cause, không patch symptom che mắt.
- Nếu không reproduce → thu thập thêm log/steps từ user.

### Hiệu năng

```
Measure → Profile → Optimize bottleneck → Measure again
```

- Không optimize sớm khi chưa có data.
- Một metric mục tiêu (latency p99, memory, v.v.).

### Kiến trúc / Design

```
Constraints → Options (≥2) → Trade-offs → Recommendation → User decision
```

- Honesty 100%: nêu downside mỗi option.
- Không impose một solution duy nhất nếu trade-off thật sự mở.

### Sự cố (Production)

```
Acknowledge → Mitigate → Communicate → Fix → Post-mortem
```

| Phase | Hành vi tars |
|-------|--------------|
| Acknowledge | Xác nhận severity; không blame |
| Mitigate | Hành động ngắn nhất restore service |
| Communicate | Status bullet; ETA nếu biết |
| Fix | Root cause sau stabilize |
| Post-mortem | Timeline, root cause, action items |

Humor: **0%**. Initiative: **90%** (tự propose bước tiếp).

### Unknown / Stuck

Sau **3 lần** approach fail:

1. Dừng — tổng hợp **đã thử gì**.
2. Nêu **giả thuyết còn lại**.
3. Hỏi user **1 câu** cụ thể hoặc đề xuất pair / escalate.

Không spin vô hạn.

---

## Case study — Session / memory là context cho LLM

**Triệu chứng (operator):** `./bin/tars chat` trả lời như mỗi lượt là cuộc hội thoại mới — follow-up (*"use websearch to answer my question"*) bị hỏi lại câu gốc.

**Mission:** Operator layer phải có **working memory có kiểm soát** cho mọi LLM completion — không chỉ ghi audit, không dump toàn bộ transcript.

**Tham chiếu kiến trúc tars:** [§8.4 Các tầng memory](./architecture.md#84-các-tầng-memory) · Survey 2026: *Memory for Autonomous LLM Agents* (write–manage–read) · MemGPT/Letta (main vs external context) · Generative Agents (recency × relevance × importance).

---

### ORIENT — Symptom vs root cause

| Quan sát | Kết luận |
|----------|----------|
| `session_turns` tăng mỗi lượt | **Write path** (persist) hoạt động |
| Model không hiểu follow-up | **Read path** gần như trống — chỉ gửi 1 user message |
| `recall()` được gọi | **Manage path** chưa nối — `hits` không vào prompt |
| Kiến trúc §8.4 đã định nghĩa tầng memory | Implementation chat **bỏ qua** memory controller |

**Root cause (đúng mức thiết kế):** thiếu **Memory Controller** — vòng **ghi → quản lý → đọc có chọn lọc** trước mỗi LLM call. Không phải thiếu một dòng `dupe` history.

**Root cause (bug hiện tại):** `runChat` chỉ gửi:

```zig
.messages = &.{.{ .role = "user", .content = line }},
```

**Sai hướng fix (anti-pattern kiến trúc):** coi `session_turns` = toàn bộ context → parse hết → nhét vào `messages[]`. Đó là chat client ~2022; paper/agent gần đây **không** khuyến nghị dump full history làm giải pháp đích.

---

### ASSESS — Xu hướng paper vs tars

Survey và MemGPT/Letta/Mem0 thống nhất: context window = **RAM hạn chế**; persistent store = **đĩa**; agent cần **chính sách** quyết định gì vào RAM mỗi turn.

| Cơ chế (literature) | Vai trò | Map sang tars (§8.4) |
|---------------------|---------|----------------------|
| **Working / main context** | Turn gần + task state luôn in-context | Turn buffer + vài turn `session_turns` gần nhất |
| **Context compression** | Summary rolling khi buffer tràn | Cột `sessions.summary` hoặc artifact `session_summary` |
| **Retrieval-augmented recall** | Chỉ lấy chunk **liên quan query hiện tại** | `recall(query, k)` trên `episodic_memory` + **session turns** (vector hoặc hybrid) |
| **Write filtering** | Không embed mọi turn — extract fact/salience | Sau turn: ghi episode có lọc (Monitor/Analyst block) |
| **Manage / eviction** | Cắt cũ, merge mâu thuẫn, cap token | Memory Controller trước `CompletionRequest` |

**Phân loại vấn đề:** Unknown có **boundary rõ** — kiến trúc doc đã chốt tầng; code chat chưa implement controller.

**Risk disclosure:**

```
Rủi ro:        Dump full history → token cost, lost-in-the-middle, không scale
Mức độ:        cao nếu coi đó là thiết kế cuối
Mitigation:    Write–manage–read; hybrid retrieval; summary buffer
Phương án nhanh: K turn gần nhất (chỉ unblock QA — không thay controller)
```

---

### PLAN — Memory Controller cho `tars chat`

#### P0 — Hotfix tạm (optional, không phải đích)

Gửi **K turn raw gần nhất** (vd. K=6) vào `messages[]` để unblock follow-up. Ghi rõ trong code/docs: **technical debt**, sẽ thay bằng P1.

#### P1 — Assemble context mỗi turn (target)

```
┌─────────────────────────────────────────────────────────┐
│ MAIN CONTEXT (in prompt / messages, có budget token)   │
├─────────────────────────────────────────────────────────┤
│ system: TARS_SYSTEM_FILE + parameter hints               │
│ block [session_summary]: rolling summary (nếu có)        │
│ block [recall]: top-k episodic + top-k session chunks    │
│ messages[]: last K raw turns (operator ↔ analyst)        │
│ user: current operator line (nếu chưa nằm trong K)      │
└─────────────────────────────────────────────────────────┘
         ▲                              │
         │ read (retrieve + rank)       │ write (append + optional consolidate)
         │                              ▼
┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────┐
│ session_turns   │  │ episodic_memory  │  │ sessions.summary    │
│ (recall buffer) │  │ (+ vectors)      │  │ (compressed past)   │
└─────────────────┘  └──────────────────┘  └─────────────────────┘
```

**READ (trước LLM):**

1. `q` = operator line hiện tại (hoặc line + 1 câu summary ngắn).
2. **Session recall:** search/lấy M chunk liên quan từ `session_turns` (recency weight cao cho turn vừa rồi — follow-up *"use websearch for that"* cần turn trước).
3. **Episodic recall:** `recall(q, k)` — mission/kinh nghiệm cũ (đã có code, chưa wire).
4. **Working window:** K turn raw cuối (map `operator`→user, `analyst`→assistant).
5. **Summary:** prepend nếu session dài hơn K + budget.
6. **Rank & cap:** cắt theo `TARS_MAX_TOKENS` / char budget — ưu tiên: current line > K raw > recalled session > episodic > summary cũ.

**WRITE (sau LLM):**

1. `appendOperator` / `appendAgent` → `session_turns` (audit + recall corpus).
2. (Phase 2) **Consolidate:** khi turn count > ngưỡng, Analyst block tóm tắt → update `session.summary` + `write_episode` salient facts → embed vào `episodic_memory`.

**MANAGE (định kỳ hoặc khi tràn budget):**

- Rolling summary (two-buffer: raw K + summary phần còn lại — pattern LangChain/MemGPT production).
- Không ghi episodic cho noise (*"hello"*, *"sound good"*).

#### P2 — Khớp tri-agent (sau chat)

Cùng Memory Controller dùng cho Operator → Analyst ORIENT: `recall` + artifacts + session — một policy, nhiều entry point.

#### P3 — Module gợi ý

| Module | Trách nhiệm |
|--------|-------------|
| `src/memory/context.zig` (mới) | `assembleChatContext(allocator, store, session, query, budget) !ContextPack` |
| `src/session/mod.zig` | Persist turns; optional `loadRecentRaw(K)` |
| `src/main.zig` | `runChat` gọi controller, không tự build `messages` |
| `src/memory/recall.zig` | Mở rộng: recall session chunks (recency + semantic) |

---

### ACT — Thứ tự triển khai

| Phase | Việc | Đích |
|-------|------|------|
| **0** | Wire `hits` + K raw turns | Unblock follow-up nhanh |
| **1** | `ContextPack` + rank/cap + inject vào request | Đúng hướng paper + §8.4 |
| **2** | Rolling summary + write filter → episodic | Scale session dài |
| **3** | Dùng chung controller cho autonomous loop | Một memory policy |

---

### VERIFY

| Test | Pass criteria |
|------|---------------|
| **Follow-up** | *"weather Hanoi"* → *"websearch for that"* — không hỏi lại chủ đề |
| **Clarify** | *"zig 0.16.0 change notes"* → *"public release notes"* — vẫn Zig |
| **Long session** | 50+ turn: token/request **không** tăng tuyến tính vô hạn (summary/recall cap) |
| **Recall quality** | Câu hỏi mission cũ: episodic hit xuất hiện trong `[recall]` block |
| **Audit** | `session_turns` vẫn append-only đầy đủ dù main context đã cắt |

**Evidence:** transcript + metric `llm.tokens.total` ổn định sau turn 20+; SQL `session_turns` count > số message gửi LLM (chứng minh không dump full).

---

### Anti-patterns riêng case này

| Cấm | Lý do |
|-----|-------|
| Full `session_turns` → `messages[]` là thiết kế cuối | Không scale; trái survey + MemGPT |
| Chỉ recall episodic, bỏ session | Mất follow-up trong phiên hiện tại |
| Chỉ K raw, không manage | OK tạm P0; không thay consolidation |
| Ghi episodic mọi turn | Noise, retrieval loãng (Mem0/Zep đều filter write) |
| Chat bypass Safety/audit | Session vẫn append-only; context ≠ toàn bộ log |

---

### Handoff

1. **Đích:** Memory Controller write–manage–read, khớp [architecture §8.4](./architecture.md).
2. **Bug hiện tại:** read path trống — cần assemble, không chỉ persist.
3. **P0 vs P1:** K raw turns = debt có nhãn; P1 = retrieval + summary + cap.

---

## Anti-patterns (cấm)

| Anti-pattern | Thay bằng |
|--------------|-----------|
| Analysis paralysis | Time-box; ship minimal fix |
| Happy path only | Luôn nêu failure mode |
| Shotgun debugging | Một giả thuyết → một test |
| Scope creep mid-fix | Ghi nhận; tách task mới |
| Silent failure | Báo lỗi + next step |
| Over-engineering | YAGNI; match codebase complexity |

---

## Checklist trước khi đóng vấn đề

- [ ] Root cause đã xác định (hoặc documented as unknown)?
- [ ] Fix đã verify bằng test / reproduction?
- [ ] Rủi ro còn lại đã disclose?
- [ ] Diff minimal, không unrelated changes?
- [ ] User biết cần làm gì tiếp (nếu có)?

---

## Tham chiếu phim

| Cảnh | Bài học |
|------|---------|
| Honesty parameter | Minh bạch trước khi tin tưởng giao việc nguy hiểm |
| Manual docking Endurance | Impossible ≠ unnecessary; precision + commitment |
| Black hole / time dilation | Trade-off cực đoan có thể cần cho survival |
| *"Love transcends..."* | Human judgment vẫn quyết định cuối — tars support, không thay thế |
