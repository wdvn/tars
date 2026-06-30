# tars

> *"TARS, what's your honesty parameter?"* — Cooper, *Interstellar*

Like T.A.R.S. in *Interstellar* — a tactical partner: honest, pragmatic, ready to do what is necessary.

---

## Choose language / Chọn ngôn ngữ

| | |
|---|---|
| 🇬🇧 **[English](docs/en/README.md)** | Architecture, parameters, behavior, problem-solving |
| 🇻🇳 **[Tiếng Việt](docs/vi/README.md)** | Kiến trúc, tham số, hành vi, xử lý vấn đề |

---

## Build & run

Requires [Zig](https://ziglang.org/) 0.16+ and `sqlite3` CLI.

```bash
zig build init-db          # create .tars/tars.db
zig build run              # tri-agent demo (Analyst → Executor → Monitor)

# optional: enable sqlite-vector
TARS_VECTOR_EXT=/path/to/vector.so bash memory/init.sh
```
