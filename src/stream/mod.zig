//! Streaming output — tokens/chunks to operator (plain, SSE, or NDJSON).

const std = @import("std");
const metrics = @import("../metrics/collector.zig");

pub const format = @import("format.zig");

pub const ChunkKind = enum {
    token,
    phase,
    tool_start,
    tool_end,
    done,
    error_msg,
};

pub const Chunk = struct {
    kind: ChunkKind,
    text: []const u8,
};

pub const Sink = struct {
    ptr: *anyopaque,
    emitFn: *const fn (ptr: *anyopaque, io: std.Io, chunk: Chunk) anyerror!void,

    /// Forward a chunk to the sink's vtable emit implementation.
    pub fn emit(self: Sink, io: std.Io, chunk: Chunk) !void {
        try self.emitFn(self.ptr, io, chunk);
    }
};

/// Pick stdout sink from TARS_STREAM_FORMAT (plain | sse | ndjson).
pub fn resolveStdout(allocator: std.mem.Allocator, io: std.Io) !Sink {
    const fmt = try format.resolveFormat(allocator, io);
    return switch (fmt) {
        .plain => StdoutSink.init(),
        .sse => SseSink.init(),
        .ndjson => NdjsonSink.init(),
    };
}

/// Writes chunks to stdout with simple prefixes (human CLI).
pub const StdoutSink = struct {
    pub fn init() Sink {
        return .{
            .ptr = @ptrCast(@constCast(&stdout_state)),
            .emitFn = emitStdout,
        };
    }

    fn emitStdout(ptr: *anyopaque, io: std.Io, chunk: Chunk) !void {
        _ = ptr;
        var buf: [512]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        const prefix: []const u8 = switch (chunk.kind) {
            .token => "",
            .phase => "\n[phase] ",
            .tool_start => "\n[tool] ",
            .tool_end => "\n[/tool] ",
            .done => "\n[done] ",
            .error_msg => "\n[error] ",
        };
        try w.interface.print("{s}{s}", .{ prefix, chunk.text });
        try w.interface.flush();
        metrics.gInc("stream.chunks.emitted", 1);
    }
};

/// Server-Sent Events sink — `event:` + `data:` frames for HTTP adapters / IDE hooks.
pub const SseSink = struct {
    pub fn init() Sink {
        return .{
            .ptr = @ptrCast(@constCast(&sse_state)),
            .emitFn = emitSse,
        };
    }

    fn emitSse(ptr: *anyopaque, io: std.Io, chunk: Chunk) !void {
        _ = ptr;
        const alloc = std.heap.page_allocator;
        const frame = format.encodeSse(alloc, chunk.kind, chunk.text) catch return;
        defer alloc.free(frame);

        var buf: [4096]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        try w.interface.print("{s}", .{frame});
        try w.interface.flush();
        metrics.gInc("stream.sse.frames", 1);
        metrics.gInc("stream.chunks.emitted", 1);
    }
};

/// Newline-delimited JSON — one `{"type","text"}` object per line (machine consumers).
pub const NdjsonSink = struct {
    pub fn init() Sink {
        return .{
            .ptr = @ptrCast(@constCast(&ndjson_state)),
            .emitFn = emitNdjson,
        };
    }

    fn emitNdjson(ptr: *anyopaque, io: std.Io, chunk: Chunk) !void {
        _ = ptr;
        const alloc = std.heap.page_allocator;
        const line = format.encodeNdjson(alloc, chunk.kind, chunk.text) catch return;
        defer alloc.free(line);

        var buf: [4096]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        try w.interface.print("{s}", .{line});
        try w.interface.flush();
        metrics.gInc("stream.ndjson.lines", 1);
        metrics.gInc("stream.chunks.emitted", 1);
    }
};

var stdout_state: u8 = 0;
var sse_state: u8 = 0;
var ndjson_state: u8 = 0;

/// Collects streamed text into a buffer (for tests / non-streaming fallback).
pub const BufferSink = struct {
    buffer: *std.ArrayList(u8),

    pub fn init(buffer: *std.ArrayList(u8)) Sink {
        return .{
            .ptr = @ptrCast(buffer),
            .emitFn = emitBuffer,
        };
    }

    fn emitBuffer(ptr: *anyopaque, _: std.Io, chunk: Chunk) !void {
        const buffer: *std.ArrayList(u8) = @ptrCast(@alignCast(ptr));
        const alloc = std.heap.page_allocator;
        try buffer.appendSlice(alloc, chunk.text);
    }
};

/// Emit executor action lifecycle events through an optional sink (SSE/NDJSON/plain).
pub fn emitToolStart(io: std.Io, sink: ?Sink, kind: []const u8, payload: []const u8) !void {
    const s = sink orelse return;
    const alloc = std.heap.page_allocator;
    const text = std.fmt.allocPrint(alloc, "{{\"kind\":\"{s}\",\"payload\":\"{s}\"}}", .{ kind, payload }) catch return;
    defer alloc.free(text);
    try s.emit(io, .{ .kind = .tool_start, .text = text });
}

pub fn emitToolEnd(io: std.Io, sink: ?Sink, kind: []const u8, success: bool, exit_code: u8) !void {
    const s = sink orelse return;
    const alloc = std.heap.page_allocator;
    const text = std.fmt.allocPrint(alloc, "{{\"kind\":\"{s}\",\"success\":{s},\"exit\":{d}}}", .{
        kind,
        if (success) "true" else "false",
        exit_code,
    }) catch return;
    defer alloc.free(text);
    try s.emit(io, .{ .kind = .tool_end, .text = text });
}
