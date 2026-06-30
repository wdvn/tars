//! Metrics wrapper around LLM Provider.

const std = @import("std");
const llm = @import("../llm/mod.zig");
const collector = @import("collector.zig");
const stream_mod = @import("../stream/mod.zig");

const Wrapped = struct {
    metrics: *collector.Metrics,
    io: std.Io,
    inner: llm.Provider,
};

/// Install metrics wrapper around inner LLM provider (single global wrap_state).
pub fn wrap(metrics: *collector.Metrics, io: std.Io, inner: llm.Provider) llm.Provider {
    const w = &wrap_state;
    w.* = .{ .metrics = metrics, .io = io, .inner = inner };
    return .{
        .ptr = @ptrCast(w),
        .completeFn = complete,
        .streamFn = streamComplete,
    };
}

/// Record request count, tokens, and wall latency around non-stream complete.
fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, request: llm.CompletionRequest) !llm.CompletionResponse {
    const w: *Wrapped = @ptrCast(@alignCast(ptr));
    const start = std.Io.Clock.Timestamp.now(w.io, .awake);
    const resp = w.inner.complete(allocator, request) catch |err| {
        collector.gInc("llm.requests.errors", 1);
        collector.gInc("llm.requests.total", 1);
        return err;
    };
    const ms = @as(f64, @floatFromInt(start.untilNow(w.io).raw.toMilliseconds()));
    collector.gInc("llm.requests.total", 1);
    collector.gInc("llm.tokens.total", @floatFromInt(resp.tokens_used));
    collector.gInc("llm.latency_ms.total", ms);
    return resp;
}

/// Stream path: count chunks via CountingSink and aggregate same LLM metrics.
fn streamComplete(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    request: llm.CompletionRequest,
    sink: stream_mod.Sink,
) !llm.CompletionResponse {
    const w: *Wrapped = @ptrCast(@alignCast(ptr));
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    var counting = CountingSink{ .inner = sink, .io = io, .chunks = 0 };
    const resp = w.inner.completeStream(allocator, io, request, counting.sink()) catch |err| {
        collector.gInc("llm.requests.errors", 1);
        collector.gInc("llm.requests.total", 1);
        return err;
    };
    const ms = @as(f64, @floatFromInt(start.untilNow(io).raw.toMilliseconds()));
    collector.gInc("llm.requests.total", 1);
    collector.gInc("llm.tokens.total", @floatFromInt(resp.tokens_used));
    collector.gInc("llm.latency_ms.total", ms);
    collector.gInc("llm.stream.chunks", @floatFromInt(counting.chunks));
    return resp;
}

const CountingSink = struct {
    inner: stream_mod.Sink,
    io: std.Io,
    chunks: u32 = 0,

    /// Build a Sink vtable that delegates to inner while counting token chunks.
    fn sink(self: *CountingSink) stream_mod.Sink {
        return .{
            .ptr = @ptrCast(self),
            .emitFn = emit,
        };
    }

    /// Increment stream/LLM chunk counters then forward to operator sink.
    fn emit(ptr: *anyopaque, io: std.Io, chunk: stream_mod.Chunk) !void {
        const self: *CountingSink = @ptrCast(@alignCast(ptr));
        if (chunk.kind == .token and chunk.text.len > 0) self.chunks += 1;
        collector.gInc("stream.chunks.emitted", 1);
        try self.inner.emit(io, chunk);
    }
};

var wrap_state: Wrapped = undefined;
