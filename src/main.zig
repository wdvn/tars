const std = @import("std");
const tars = @import("tars");

/// CLI entry: `tars` (demo), `tars chat`, or `tars report [--json]`.
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Route subcommands before falling through to the full runtime demo.
    const args = try init.minimal.args.toSlice(gpa);
    defer gpa.free(args);

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "chat")) {
            try runChat(gpa, io);
            return;
        }
        if (std.mem.eql(u8, args[1], "report")) {
            try runReport(gpa, io, args.len > 2 and std.mem.eql(u8, args[2], "--json"));
            return;
        }
        if (std.mem.eql(u8, args[1], "embed")) {
            if (args.len > 2 and std.mem.eql(u8, args[2], "pull")) {
                try runEmbedPull(gpa, io);
                return;
            }
        }
    }

    try runDemo(gpa, io);
}

/// Wire global metrics handle for cross-module instrumentation during a command.
fn initMetrics(gpa: std.mem.Allocator, command: []const u8, out: *tars.metrics.Metrics) !void {
    out.* = try tars.metrics.Metrics.init(gpa, command, "tars");
    tars.metrics.setGlobal(out);
}

/// Stream completion with stub fallback when the resolved provider cannot reach its backend.
fn completeStreamWithFallback(
    gpa: std.mem.Allocator,
    io: std.Io,
    w: *std.Io.Writer,
    metrics_state: *tars.metrics.Metrics,
    provider: *tars.llm.Provider,
    req: tars.llm.CompletionRequest,
    sink: tars.stream.Sink,
) !tars.llm.CompletionResponse {
    return provider.completeStream(gpa, io, req, sink) catch |err| {
        try w.print("  stream failed ({s}) — stub fallback\n", .{@errorName(err)});
        try w.flush();
        provider.* = tars.metrics.instrumentProvider(metrics_state, io, tars.llm.StubProvider.init());
        return provider.completeStream(gpa, io, req, sink);
    };
}

/// Persist in-memory counters, print report, then tear down the global handle.
fn finishMetrics(gpa: std.mem.Allocator, io: std.Io, store: *tars.memory.store.Store, m: *tars.metrics.Metrics, w: *std.Io.Writer, json: bool) !void {
    try tars.metrics.persist.flush(m, store, io);
    const db = try tars.metrics.report.loadDbTotals(store, io, gpa);
    if (json) {
        try tars.metrics.report.printJson(gpa, w, m, db);
        try w.print("\n", .{});
    } else {
        try tars.metrics.report.printHuman(w, m, db);
        try tars.metrics.report.printHistory(store, io, w);
    }
    try w.flush();
    tars.metrics.setGlobal(null);
    m.deinit();
}

/// Read-only metrics query against SQLite (no live instrumentation).
fn runReport(gpa: std.mem.Allocator, io: std.Io, json: bool) !void {
    var store = try tars.memory.store.Store.init(gpa, ".tars/tars.db");
    defer store.deinit();
    try store.applySchema(io);

    var m = try tars.metrics.Metrics.init(gpa, "report", "query");
    defer m.deinit();

    const db = try tars.metrics.report.loadDbTotals(&store, io, gpa);

    var stdout_buffer: [16384]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const w = &stdout_writer.interface;

    if (json) {
        try tars.metrics.report.printJson(gpa, w, &m, db);
        try w.print("\n", .{});
    } else {
        try w.print("T.A.R.S. metrics catalog (registry — baseline zeros for query-only run)\n\n", .{});
        try tars.metrics.report.printHuman(w, &m, db);
        try tars.metrics.report.printHistory(&store, io, w);
    }
    try w.flush();
}

/// Pull embedding model via Ollama (`TARS_EMBED_MODEL`, default qwen3-embedding:0.6b).
fn runEmbedPull(gpa: std.mem.Allocator, io: std.Io) !void {
    var cfg = try tars.memory.embed.Config.load(gpa, io);
    defer cfg.deinit(gpa);

    if (!std.mem.eql(u8, cfg.resolvedProvider(), "ollama")) {
        var stderr_buffer: [512]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
        try stderr_writer.interface.print("TARS_EMBED_PROVIDER must be ollama (or set TARS_EMBED_MODEL)\n", .{});
        try stderr_writer.interface.flush();
        return error.ProviderNotOllama;
    }

    try tars.memory.embed.pullModel(gpa, io);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const w = &stdout_writer.interface;
    try w.print("Pulled embedding model: {s} @ {s}\n", .{ cfg.model, cfg.ollama_host });
    try w.flush();
}

/// End-to-end showcase of streaming, perception, recall, session, loop, and metrics.
fn runDemo(gpa: std.mem.Allocator, io: std.Io) !void {
    const db_path = ".tars/tars.db";
    var store = try tars.memory.store.Store.init(gpa, db_path);
    defer store.deinit();

    try store.applySchema(io);

    const mission_id = "demo-runtime";
    const sink = tars.stream.resolveStdout(gpa, io) catch tars.stream.StdoutSink.init();

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const w = &stdout_writer.interface;

    var metrics_state: tars.metrics.Metrics = undefined;
    try initMetrics(gpa, "demo", &metrics_state);
    defer finishMetrics(gpa, io, &store, &metrics_state, w, false) catch {};

    try w.print("tars runtime demo — streaming · perception · recall · session · loop\n\n", .{});
    try w.flush();

    try w.print("[1] Streaming LLM\n", .{});
    try w.flush();
    // Resolve provider from env (OpenAI / Anthropic / stub) and wrap with metrics.
    var llm_ctx = try tars.llm.resolve(gpa, io);
    defer llm_ctx.deinit();
    defer tars.llm.deinitRuntime(gpa);
    var provider = tars.metrics.instrumentProvider(&metrics_state, io, llm_ctx.provider());
    try w.print("  provider: {s}\n", .{llm_ctx.kindName()});
    try w.flush();

    const runtime_cfg = tars.llm.runtimeConfig();
    const system_prompt = if (runtime_cfg) |rc| if (rc.system_prompt.len > 0) rc.system_prompt else "T.A.R.S." else "T.A.R.S.";

    const stream_req = tars.llm.CompletionRequest{
        .config = .{ .max_tokens = if (runtime_cfg) |rc| rc.max_tokens else 4096 },
        .system = system_prompt,
        .messages = &.{.{ .role = "user", .content = "status report" }},
        .output_schema = "{}",
    };
    const stream_resp = try completeStreamWithFallback(gpa, io, w, &metrics_state, &provider, stream_req, sink);
    defer gpa.free(stream_resp.content_json);
    try w.print("\n  tokens: {d}\n\n", .{stream_resp.tokens_used});

    try w.print("[2] Codebase perception\n", .{});
    const evidence = try tars.perception.gatherEvidence(gpa, io, ".", &.{ "build.zig", "src/root.zig" });
    defer gpa.free(evidence);
    try w.print("  evidence bytes: {d}\n", .{evidence.len});

    const grep_hits = try tars.perception.grep.search(gpa, io, ".", "MissionContext", 5);
    defer gpa.free(grep_hits);
    try w.print("  grep MissionContext: {d} byte(s)\n\n", .{grep_hits.len});

    try w.print("[3] Episodic memory + semantic recall\n", .{});
    const embed_ctx = try tars.memory.embed.resolve(gpa, io);
    defer tars.memory.embed.deinitRuntime(gpa);
    _ = embed_ctx;
    try w.print("  embed: {s} dim={d}\n", .{
        if (tars.memory.embed.runtimeConfig()) |c| c.resolvedProvider() else "hash",
        tars.memory.embed.dimension(),
    });
    // Seed two episodes so recall has vectors to rank against the query.
    try tars.core.mission.writeEpisodeFromOutcome(gpa, &store, io, mission_id, "analyst", "Tri-agent skeleton uses ORIENT ASSESS PLAN ACT VERIFY phases", &.{ "architecture", "demo" });
    try tars.core.mission.writeEpisodeFromOutcome(gpa, &store, io, mission_id, "monitor", "Verify phase checks executor output and publishes handoff", &.{ "verify" });

    const hits = try tars.memory.recall.recall(gpa, &store, io, "verify handoff monitor", 2);
    defer if (hits.len > 0) tars.memory.recall.freeHitsSlice(gpa, hits);
    for (hits) |h| try w.print("  recall score={d:.3}: {s}\n", .{ h.score, h.content[0..@min(h.content.len, 60)] });
    try w.print("\n", .{});

    try w.print("[4] Multi-turn session\n", .{});
    var sess = try tars.session.Session.create(gpa, store, io, mission_id);
    defer sess.deinit(gpa);
    try sess.appendOperator("What is the mission loop?");
    try sess.appendAgent("analyst", "ORIENT → ASSESS → PLAN → ACT → VERIFY with loop-back.");
    const ctx_lines = try sess.recentContext(gpa, 10);
    defer gpa.free(ctx_lines);
    try w.print("  session {s}: {d} byte(s) context\n\n", .{ sess.id, ctx_lines.len });

    try w.print("[5] MCP bridge (JSON-RPC)\n", .{});
    if (tars.mcp.client.Client.fromEnv(gpa, io)) |client| {
        defer client.deinit();
        const tools = client.listTools(gpa, io) catch |err| switch (err) {
            else => try tars.mcp.client.stubCall(gpa, "list"),
        };
        defer gpa.free(tools);
        try w.print("  MCP tools/list: {d} byte(s)\n\n", .{tools.len});
    } else {
        const stub = try tars.mcp.client.stubCall(gpa, "filesystem__read");
        defer gpa.free(stub);
        try w.print("  {s} (set TARS_MCP_CMD for live JSON-RPC MCP)\n\n", .{stub});
    }

    try w.print("[5b] Skills (SKILL.md)\n", .{});
    const skill_list = tars.skills.loader.listSkills(gpa, io) catch "{}";
    defer gpa.free(skill_list);
    try w.print("  {s}\n\n", .{skill_list});

    try w.print("[6] Autonomous loop\n", .{});
    // Pass perception evidence into mission ctx; loop may replace it during ORIENT.
    var ctx = tars.core.mission.defaultContext(mission_id, "Runtime capability demo");
    ctx.evidence = evidence;

    const plan = tars.types.ApprovedPlan{
        .mission_id = mission_id,
        .steps = &.{
            .{ .kind = .shell, .payload = "echo tars-loop-ok" },
            .{ .kind = .skill, .payload = "list" },
            .{ .kind = .mcp, .payload = "filesystem__read:{\"path\":\"build.zig\"}" },
            .{ .kind = .git, .payload = "status --short" },
        },
        .rollback = "echo tars-plan-rollback-ok",
    };

    const loop_result = try tars.core.loop.runAutonomous(gpa, io, store, provider, sink, .{
        .max_iterations = 6,
        .verify_commands = &.{"test -f build.zig"},
        .perception_paths = &.{ "build.zig" },
        .repo_root = ".",
    }, &ctx, &plan);

    try w.print("  iterations: {d}, status: {s}\n", .{ loop_result.iterations, loop_result.final_status.name() });
    if (loop_result.last_verify) |vo| {
        switch (vo) {
            .pass => |h| {
                try w.print("  verify: PASS\n", .{});
                gpa.free(h.summary_json);
            },
            .fail => |l| {
                try w.print("  verify: FAIL → {s}\n", .{l.reason});
                gpa.free(l.detail_json);
            },
        }
    }

    try w.print("\n[7] Operational metrics\n", .{});
}

/// Interactive REPL with recall-augmented streaming responses.
fn runChat(gpa: std.mem.Allocator, io: std.Io) !void {
    const db_path = ".tars/tars.db";
    var store = try tars.memory.store.Store.init(gpa, db_path);
    defer store.deinit();
    try store.applySchema(io);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const w = &stdout_writer.interface;

    var metrics_state: tars.metrics.Metrics = undefined;
    try initMetrics(gpa, "chat", &metrics_state);
    defer finishMetrics(gpa, io, &store, &metrics_state, w, false) catch {};

    const embed_ctx = try tars.memory.embed.resolve(gpa, io);
    defer tars.memory.embed.deinitRuntime(gpa);
    _ = embed_ctx;

    var sess = try tars.session.Session.create(gpa, store, io, "chat");
    defer sess.deinit(gpa);

    var llm_ctx = try tars.llm.resolve(gpa, io);
    defer llm_ctx.deinit();
    defer tars.llm.deinitRuntime(gpa);
    const provider = tars.metrics.instrumentProvider(&metrics_state, io, llm_ctx.provider());
    const sink = tars.stream.resolveStdout(gpa, io) catch tars.stream.StdoutSink.init();

    const runtime_cfg = tars.llm.runtimeConfig();
    const system_prompt = if (runtime_cfg) |rc| if (rc.system_prompt.len > 0) rc.system_prompt else "T.A.R.S. crew analyst" else "T.A.R.S. crew analyst";

    const ctx_cfg = try tars.memory.context.Config.load(gpa, io);

    try w.print("T.A.R.S. chat ({s}, session {s}). Empty line to exit.\n> ", .{ llm_ctx.kindName(), sess.id });
    try w.flush();

    var reader_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &reader_buffer);

    while (true) {
        const raw = stdin_reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        const line = std.mem.trim(u8, raw, " \r\n");
        if (line.len == 0) break;

        try sess.appendOperator(line);

        var pack = try tars.memory.context.assembleChatContext(gpa, io, &store, &sess, line, system_prompt, ctx_cfg);
        defer pack.deinit(gpa);

        var turn = try tars.core.chat.runTurn(gpa, io, &store, &sess, provider, sink, line, &pack, .{
            .repo_root = ".",
        });
        defer turn.deinit(gpa);

        if (!turn.streamed) {
            try w.print("{s}", .{turn.response});
        }
        try sess.appendAgent("analyst", turn.response);
        try tars.memory.context.manageSessionSummary(gpa, &sess, ctx_cfg);
        try w.print("\n> ", .{});
        try w.flush();
    }

    try w.print("\n--- metrics ---\n", .{});
}
