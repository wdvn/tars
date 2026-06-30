# T.A.R.S. demo skill

Use this skill pack when demonstrating Executor skill loading.

## Steps

1. List skills: action kind `skill`, payload `list`
2. Load this skill: payload `tars-demo`
3. Combine with MCP tools via `mcp` action when `TARS_MCP_CMD` is set

## Stream formats

Set `TARS_STREAM_FORMAT=sse` or `ndjson` for machine-readable executor/LLM events.
