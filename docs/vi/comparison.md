# T.A.R.S. vs. mini-agent — Bảng so sánh

**Ngôn ngữ:** [English](../en/comparison.md) | **Tiếng Việt**

So sánh giữa **tars** (dự án này) và **[mini-agent](https://github.com/wdvn/mini)** — cả hai đều là AI agent viết bằng Zig nhưng theo hai triết lý khác nhau.

[← Mục lục](./README.md) · [Kiến trúc](./architecture.md) · [Tham số](./parameters.md) · [Hành vi](./behavior.md) · [Xử lý vấn đề](./problem-solving.md)

---

## 1. Tổng quan

| | **tars** | **mini-agent** (`wdvn/mini`) |
|---|----------|------------------------------|
| **Mục tiêu** | Agent tự trị chiến thuật theo mô hình kiến trúc, lấy cảm hứng từ T.A.R.S. trong *Interstellar* | AI agent terminal nhỏ gọn, thực dụng, dùng được ngay |
| **Triết lý** | Thiết kế dẫn dắt: kiến trúc, an toàn, khả năng kiểm toán | Tối giản, không phụ thuộc, 1 binary chạy được ngay |
| **Ngôn ngữ** | Zig 0.16+ | Zig 0.16.0 (nâng từ 0.15.2) |
| **Quy mô** | ~4.4k dòng Zig | ~4.5k dòng Zig |
| **Trạng thái** | Skeleton + runtime demo (giai đoạn đầu) | Bản 1.0.0 hoàn chỉnh, ~12MB binary |
| **License** | (xem `LICENSE`) | MIT |

---

## 2. Kiến trúc

| Khía cạnh | **tars** | **mini-agent** |
|-----------|----------|----------------|
| **Mô hình agent** | **Tri-agent**: Analyst (lý luận) · Executor (hành động) · Monitor (theo dõi) | **Single agentic loop** (`AgentLoop`) |
| **Vòng lặp nhận thức** | ORIENT → ASSESS → PLAN → ACT → VERIFY có loop-back | Vòng lặp tool đơn giản (tối đa 20 iterations) |
| **Phân lớp** | 5 lớp L0–L4 (Infra · Tri-Agent · Cognitive · Policy · Operator) | Phẳng: main → agent → backend/tools |
| **Điều phối** | Mission Controller + agent event bus | Trực tiếp trong `agent.zig` |
| **Vị trí LLM** | Nhúng trong Reasoning blocks của Analyst (không phải orchestrator) | Là trung tâm vòng lặp, tự quyết gọi tool |

---

## 3. Khả năng (Capabilities)

| Khía cạnh | **tars** | **mini-agent** |
|-----------|----------|----------------|
| **LLM backend** | Anthropic, OpenAI | OpenAI-compatible, Anthropic Claude, Ollama (local) |
| **Streaming** | Có (`stream/`) | Có (SSE / NDJSON) |
| **Bộ nhớ** | SQLite + sqlite-vector: episodic memory, semantic recall, missions, audit log | In-memory history với auto-compacting |
| **Tools** | Executor action blocks: shell, file_editor, git_ops, mcp_bridge; perception: file_reader, grep | 9 built-in: bash, file_read/write/edit, glob, grep, http_request, web_search, skills |
| **MCP** | Có (`mcp/client`) | Có (JSON-RPC over stdio, prefix `server__tool`) |
| **An toàn** | Safety Guard (ranh giới cứng P5) + Monitor verify (test/lint/diff) | Blocklist pattern bash + tool allow/blocklist + chặn ghi `/etc /sys /proc /dev` |
| **Metrics / quan sát** | Module `metrics` riêng (collector, registry, persist, report) + audit log | Không có riêng |
| **Kiểm toán** | `audit_log` append-only do Monitor ghi | Không |

---

## 4. Giao diện & vận hành

| Khía cạnh | **tars** | **mini-agent** |
|-----------|----------|----------------|
| **Chế độ chạy** | `chat` (REPL), `report`, demo runtime | REPL tương tác + single-shot (`-e`) |
| **Slash commands** | Chưa | `/help`, `/clear`, `/model`, `/quit` |
| **Đổi backend runtime** | Qua biến môi trường | `/model <backend> <model>` ngay trong REPL |
| **Cấu hình** | Env (`TARS_VECTOR_EXT`, `TARS_MCP_CMD`) | Auto-load `.env` (CWD, `~/.mini/.env`), nhiều env var |
| **System prompt** | Trong code reasoning blocks | File `.md` tùy chỉnh (`MINI_SYSTEM_FILE`) |
| **Phân phối** | `zig build` | 1 binary, cross-compile, cài vào PATH |
| **Ví dụ kèm theo** | Demo nội bộ | Newspaper agent (HN + arXiv digest) |

---

## 5. Tài liệu

| Khía cạnh | **tars** | **mini-agent** |
|-----------|----------|----------------|
| **Định dạng** | Bộ docs song ngữ (EN/VI): architecture, parameters, behavior, problem-solving | README chi tiết + `docs/plan.md` |
| **Trọng tâm** | Thiết kế, triết lý, hợp đồng giữa các agent | Hướng dẫn dùng, cấu hình, tool, đóng góp |

---

## 6. Kết luận ngắn gọn

| Chọn... | Khi bạn cần... |
|---------|----------------|
| **tars** | Một khung kiến trúc agent có cấu trúc rõ, tách vai trò, an toàn và kiểm toán chặt — phù hợp xây dựng dài hạn, có chủ đích thiết kế |
| **mini-agent** | Một agent terminal gọn nhẹ, chạy được ngay, đa backend, nhiều tool sẵn — phù hợp dùng hằng ngày và tự động hóa nhanh |

Tóm lại: **tars** thiên về *kiến trúc và nguyên tắc* (tri-agent, bộ nhớ semantic, an toàn, metrics), còn **mini-agent** thiên về *tính thực dụng và sẵn sàng sử dụng* (1 binary, đa backend, 9 tool, ví dụ thật).

[← Mục lục](./README.md)
