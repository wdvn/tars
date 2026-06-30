//! MCP client — JSON-RPC 2.0 over stdio (newline-delimited).
//! Set TARS_MCP_CMD to launch server, e.g. `npx -y @modelcontextprotocol/server-filesystem /tmp`

const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");
const tool_ref = @import("tool_ref.zig");

pub const ClientError = error{
    NotConfigured,
    SpawnFailed,
    RpcFailed,
    OutOfMemory,
};

pub const Client = struct {
    cmd: []const u8,
    allocator: std.mem.Allocator,

    /// Build client from TARS_MCP_CMD env; null when unset or empty.
    pub fn fromEnv(allocator: std.mem.Allocator, io: std.Io) ?Client {
        const result = std.process.run(allocator, io, .{
            .argv = &.{ "bash", "-c", "printf %s \"$TARS_MCP_CMD\"" },
        }) catch return null;
        defer allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code != 0) {
                allocator.free(result.stdout);
                return null;
            },
            else => {
                allocator.free(result.stdout);
                return null;
            },
        }
        if (result.stdout.len == 0) {
            allocator.free(result.stdout);
            return null;
        }
        return .{ .cmd = result.stdout, .allocator = allocator };
    }

    pub fn deinit(self: *const Client) void {
        self.allocator.free(self.cmd);
    }

    /// Run MCP initialize + notifications/initialized before tool calls.
    pub fn handshake(self: *const Client, allocator: std.mem.Allocator, io: std.Io) ClientError!void {
        const init_req = try jsonrpc.buildRequest(allocator, 0, "initialize", jsonrpc.initializeParams());
        defer allocator.free(init_req);
        const init_resp = self.sendLine(allocator, io, init_req) catch return ClientError.RpcFailed;
        defer allocator.free(init_resp);
        if (jsonrpc.hasError(init_resp)) return ClientError.RpcFailed;

        const notif = "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n";
        _ = self.sendLine(allocator, io, notif) catch return ClientError.RpcFailed;
    }

    /// Invoke tools/call; tool_name may use `server__tool` prefix (server field is informational).
    pub fn callTool(
        self: *const Client,
        allocator: std.mem.Allocator,
        io: std.Io,
        tool_name: []const u8,
        args_json: []const u8,
    ) ClientError![]const u8 {
        self.handshake(allocator, io) catch {};

        const ref = try tool_ref.parse(allocator, tool_name);
        defer tool_ref.deinit(allocator, ref);

        const params = try jsonrpc.toolsCallParams(allocator, ref.tool, args_json);
        defer allocator.free(params);

        const req = try jsonrpc.buildRequest(allocator, 1, "tools/call", params);
        defer allocator.free(req);

        const raw = try self.sendLine(allocator, io, req);
        defer allocator.free(raw);

        if (jsonrpc.hasError(raw)) return ClientError.RpcFailed;

        const result_json = jsonrpc.extractResult(allocator, raw) catch return ClientError.RpcFailed;
        defer allocator.free(result_json);

        return jsonrpc.extractToolText(allocator, result_json) catch return ClientError.RpcFailed;
    }

    /// List tools via tools/list JSON-RPC.
    pub fn listTools(
        self: *const Client,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) ClientError![]const u8 {
        self.handshake(allocator, io) catch {};

        const req = try jsonrpc.buildRequest(allocator, 2, "tools/list", jsonrpc.emptyParams());
        defer allocator.free(req);

        const raw = try self.sendLine(allocator, io, req);
        defer allocator.free(raw);

        if (jsonrpc.hasError(raw)) return ClientError.RpcFailed;
        return jsonrpc.extractResult(allocator, raw) catch return ClientError.RpcFailed;
    }

    /// Pipe one JSON-RPC line to MCP server stdin via temp file (avoids shell injection).
    fn sendLine(self: *const Client, allocator: std.mem.Allocator, io: std.Io, line: []const u8) ClientError![]const u8 {
        const metrics = @import("../metrics/collector.zig");
        metrics.gInc("mcp.rpc.requests", 1);

        const req_path = try writeTempLine(allocator, io, line);
        defer cleanupTemp(allocator, io, req_path);

        const script = try std.fmt.allocPrint(allocator, "cat '{s}' | {s}", .{ req_path, self.cmd });
        defer allocator.free(script);

        const result = std.process.run(allocator, io, .{
            .argv = &.{ "bash", "-c", script },
        }) catch return ClientError.SpawnFailed;
        defer allocator.free(result.stderr);

        switch (result.term) {
            .exited => |code| {
                if (code != 0) {
                    allocator.free(result.stdout);
                    return ClientError.RpcFailed;
                }
                return result.stdout;
            },
            else => {
                allocator.free(result.stdout);
                return ClientError.SpawnFailed;
            },
        }
    }
};

/// Deterministic JSON when MCP is not configured.
pub fn stubCall(allocator: std.mem.Allocator, tool_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{{\"tool\":\"{s}\",\"status\":\"mcp_stub\",\"note\":\"set TARS_MCP_CMD\"}}", .{tool_name});
}

fn writeTempLine(allocator: std.mem.Allocator, io: std.Io, line: []const u8) ClientError![]const u8 {
    const path = try std.fmt.allocPrint(allocator, "/tmp/tars-mcp-{x}.json", .{std.hash.Wyhash.hash(0, line)});
    const enc_size = std.base64.standard.Encoder.calcSize(line.len);
    const encoded = try allocator.alloc(u8, enc_size);
    defer allocator.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, line);

    const cmd = try std.fmt.allocPrint(allocator, "python3 -c 'import base64,sys; open(sys.argv[1],\"wb\").write(base64.b64decode(sys.argv[2]))' '{s}' '{s}'", .{ path, encoded });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return ClientError.SpawnFailed;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| if (code != 0) return ClientError.SpawnFailed,
        else => return ClientError.SpawnFailed,
    }
    return path;
}

fn cleanupTemp(allocator: std.mem.Allocator, io: std.Io, path: []const u8) void {
    _ = std.process.run(allocator, io, .{ .argv = &.{ "rm", "-f", path } }) catch {};
    allocator.free(path);
}
