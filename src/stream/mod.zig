//! Streaming output — tokens/chunks to operator (stdout or IDE adapter).

const std = @import("std");

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

    pub fn emit(self: Sink, io: std.Io, chunk: Chunk) !void {
        try self.emitFn(self.ptr, io, chunk);
    }
};

/// Writes chunks to stdout with simple prefixes.
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
    }
};

var stdout_state: u8 = 0;

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
