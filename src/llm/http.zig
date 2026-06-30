//! HTTP transport for LLM APIs via curl.

const std = @import("std");
const metrics = @import("../metrics/collector.zig");

pub const HttpError = error{
    CurlFailed,
    OutOfMemory,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    status: u16,
    body: []const u8,
};

pub fn post(
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    headers: []const Header,
    body: []const u8,
) HttpError!Response {
    metrics.gInc("http.requests.total", 1);
    const body_path = try writeTempBody(allocator, io, body);
    defer cleanupTemp(allocator, io, body_path);

    var header_storage: std.ArrayList([]const u8) = .empty;
    defer {
        for (header_storage.items) |h| allocator.free(h);
        header_storage.deinit(allocator);
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    const data_arg = try std.fmt.allocPrint(allocator, "@{s}", .{body_path});
    defer allocator.free(data_arg);

    try argv.appendSlice(allocator, &.{ "curl", "-sS", "-w", "\\n---TARS_HTTP:%{http_code}", "-X", "POST", url });
    for (headers) |h| {
        const header = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ h.name, h.value });
        try header_storage.append(allocator, header);
        try argv.append(allocator, "-H");
        try argv.append(allocator, header);
    }
    try argv.append(allocator, "--data-binary");
    try argv.append(allocator, data_arg);

    const result = std.process.run(allocator, io, .{ .argv = argv.items }) catch {
        metrics.gInc("http.requests.errors", 1);
        return HttpError.CurlFailed;
    };
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            metrics.gInc("http.requests.errors", 1);
            allocator.free(result.stdout);
            return HttpError.CurlFailed;
        },
        else => {
            allocator.free(result.stdout);
            return HttpError.CurlFailed;
        },
    }

    return splitStatus(allocator, result.stdout) catch |err| switch (err) {
        error.OutOfMemory => return HttpError.OutOfMemory,
        else => {
            allocator.free(result.stdout);
            return HttpError.CurlFailed;
        },
    };
}

pub const StreamChunkFn = *const fn (ctx: *anyopaque, chunk: []const u8) anyerror!void;

pub fn postStream(
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    headers: []const Header,
    body: []const u8,
    ctx: *anyopaque,
    onChunk: StreamChunkFn,
) HttpError!Response {
    metrics.gInc("http.requests.total", 1);
    const body_path = try writeTempBody(allocator, io, body);
    defer cleanupTemp(allocator, io, body_path);

    var header_storage: std.ArrayList([]const u8) = .empty;
    defer {
        for (header_storage.items) |h| allocator.free(h);
        header_storage.deinit(allocator);
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    const data_arg = try std.fmt.allocPrint(allocator, "@{s}", .{body_path});
    defer allocator.free(data_arg);

    try argv.appendSlice(allocator, &.{ "curl", "-sS", "-N", "-w", "\\n---TARS_HTTP:%{http_code}", "-X", "POST", url });
    for (headers) |h| {
        const header = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ h.name, h.value });
        try header_storage.append(allocator, header);
        try argv.append(allocator, "-H");
        try argv.append(allocator, header);
    }
    try argv.append(allocator, "--data-binary");
    try argv.append(allocator, data_arg);

    var child = std.process.spawn(io, .{
        .argv = argv.items,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch {
        metrics.gInc("http.requests.errors", 1);
        return HttpError.CurlFailed;
    };
    defer child.kill(io);

    var acc: std.ArrayList(u8) = .empty;
    errdefer acc.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    const stdout = child.stdout orelse return HttpError.CurlFailed;
    var line_carry: std.ArrayList(u8) = .empty;
    defer line_carry.deinit(allocator);

    while (true) {
        const n = stdout.readStreaming(io, &.{&read_buf}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return HttpError.CurlFailed,
        };
        if (n == 0) break;

        try acc.appendSlice(allocator, read_buf[0..n]);
        try line_carry.appendSlice(allocator, read_buf[0..n]);

        while (std.mem.indexOfScalar(u8, line_carry.items, '\n')) |nl| {
            const line = line_carry.items[0..nl];
            const trimmed = std.mem.trim(u8, line, " \r");
            if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "---TARS_HTTP:")) {
                onChunk(ctx, trimmed) catch return HttpError.CurlFailed;
            }
            const rest = line_carry.items[nl + 1 ..];
            line_carry.clearRetainingCapacity();
            try line_carry.appendSlice(allocator, rest);
        }
    }

    if (line_carry.items.len > 0) {
        const trimmed = std.mem.trim(u8, line_carry.items, " \r");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "---TARS_HTTP:")) {
            onChunk(ctx, trimmed) catch return HttpError.CurlFailed;
        }
    }

    const term = child.wait(io) catch return HttpError.CurlFailed;
    switch (term) {
        .exited => |code| if (code != 0) {
            metrics.gInc("http.requests.errors", 1);
            return HttpError.CurlFailed;
        },
        else => {
            metrics.gInc("http.requests.errors", 1);
            return HttpError.CurlFailed;
        },
    }

    return splitStatus(allocator, try acc.toOwnedSlice(allocator)) catch |err| switch (err) {
        error.OutOfMemory => return HttpError.OutOfMemory,
        else => return HttpError.CurlFailed,
    };
}

fn splitStatus(allocator: std.mem.Allocator, raw: []u8) SplitError!Response {
    const marker = "---TARS_HTTP:";
    if (std.mem.lastIndexOf(u8, raw, marker)) |idx| {
        const code_str = std.mem.trim(u8, raw[idx + marker.len ..], " \r\n");
        const status = std.fmt.parseInt(u16, code_str, 10) catch return error.InvalidStatus;
        const body = try allocator.dupe(u8, std.mem.trim(u8, raw[0..idx], " \r\n"));
        allocator.free(raw);
        return .{ .status = status, .body = body };
    }
    const body = try allocator.dupe(u8, raw);
    return .{ .status = 200, .body = body };
}

fn writeTempBody(allocator: std.mem.Allocator, io: std.Io, body: []const u8) HttpError![]const u8 {
    const path = try std.fmt.allocPrint(allocator, "/tmp/tars-llm-{x}.json", .{std.hash.Wyhash.hash(0, body)});
    const enc_size = std.base64.standard.Encoder.calcSize(body.len);
    const encoded = try allocator.alloc(u8, enc_size);
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, body);

    const cmd = try std.fmt.allocPrint(allocator, "python3 -c 'import base64,sys; open(sys.argv[1],\"wb\").write(base64.b64decode(sys.argv[2]))' '{s}' '{s}'", .{ path, encoded });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return HttpError.CurlFailed;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| if (code != 0) return HttpError.CurlFailed,
        else => return HttpError.CurlFailed,
    }
    return path;
}

fn cleanupTemp(allocator: std.mem.Allocator, io: std.Io, path: []const u8) void {
    _ = std.process.run(allocator, io, .{ .argv = &.{ "rm", "-f", path } }) catch {};
    allocator.free(path);
}

const SplitError = error{ InvalidStatus, OutOfMemory };
