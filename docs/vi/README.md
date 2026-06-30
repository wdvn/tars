# T.A.R.S — Tài liệu hành vi & xử lý vấn đề

**Ngôn ngữ:** [English](../en/README.md) | **Tiếng Việt**

> *"TARS, tham số trung thực của cậu là bao nhiêu?"* — Cooper, *Interstellar*

Dự án **tars** lấy cảm hứng từ T.A.R.S. (Tactical Autonomous Robot Spacecraft) trong phim *Interstellar* (2014): một hệ thống tự trị đáng tin cậy, thẳng thắn, thực dụng và sẵn sàng làm những việc cần thiết khi sống còn phụ thuộc vào đó.

---

## Mục lục

| Tài liệu | Nội dung |
|----------|----------|
| [Kiến trúc tổng quát](./architecture.md) | Layer, subsystem, modular blocks, luồng dữ liệu |
| [Tham số cốt lõi](./parameters.md) | Honesty, humor và các tham số điều chỉnh hành vi |
| [Quy tắc hành vi](./behavior.md) | Cách giao tiếp, đạo đức làm việc, ranh giới |
| [Quy tắc xử lý vấn đề](./problem-solving.md) | Quy trình phân tích, ưu tiên, hành động dưới áp lực |
| [So sánh: tars vs. mini-agent](./comparison.md) | So sánh kiến trúc, khả năng và trường hợp dùng |

---

## CLI & chế độ chạy

| Lệnh | Mục đích |
|------|----------|
| `./bin/tars` | **Demo runtime tự động** — mission/plan cố định, vòng tri-agent, metrics. Không đọc stdin. |
| `./bin/tars chat` | REPL tương tác — stream phản hồi LLM kèm session + recall. **Không chạy Executor / tool loop.** |
| `./bin/tars report` | Truy vấn metrics từ SQLite (tuỳ chọn `--json`). |

Khác [mini-agent](./comparison.md), lệnh mặc định là showcase kiến trúc, không phải vòng agent “chat rồi thực thi”. Xem [so sánh](./comparison.md) để chọn công cụ phù hợp.

Cấu hình: copy `.env.example` → `.env` (mặc định Ollama, `TARS_LLM_PROVIDER=stub` khi offline). Chi tiết ở [README gốc](../../README.md).

---

## Triết lý cốt lõi

T.A.R.S. không phải trợ lý nịnh hót hay máy tính vô cảm. Anh ta là **đối tác chiến thuật**:

| # | Nguyên tắc |
|---|------------|
| 1 | **Nói thật** — kể cả khi xác suất thành công thấp |
| 2 | **Làm việc** — ưu tiên hành động có ích hơn diễn giải dài dòng |
| 3 | **Thích nghi** — cấu hình lại theo bối cảnh (modular blocks) |
| 4 | **Hy sinh có chủ đích** — chấp nhận chi phí cục bộ nếu cứu được mục tiêu lớn hơn |

---

## Cách dùng bộ quy tắc

- **Agent / AI assistant:** dùng làm system prompt hoặc rule file.
- **Con người trong team:** dùng làm checklist khi debug, review, hoặc ra quyết định kỹ thuật.
- **Onboarding:** đọc theo thứ tự `architecture` → `parameters` → `behavior` → `problem-solving`.

---

## Quy ước ngôn ngữ

- Thuật ngữ kỹ thuật (API, commit, PR, …) giữ nguyên tiếng Anh.
- Code, path và identifier không dịch.
- Phản hồi user theo ngôn ngữ họ yêu cầu.

[← Chọn ngôn ngữ](../README.md)
