//! MCP client — JSON-RPC over stdio (external tool servers).
//! Set TARS_MCP_CMD to launch server, e.g. `npx -y @modelcontextprotocol/server-filesystem /tmp`

const std = @import("std");

pub const ClientError = error{
    NotConfigured,
    SpawnFailed,
    RpcFailed,
    OutOfMemory,
};

pub const Client = struct {
    cmd: []const u8,
    allocator: std.mem.Allocator,

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

    /// Invoke tools/call with stub JSON body when MCP server unavailable.
    pub fn callTool(
        self: *const Client,
        allocator: std.mem.Allocator,
        io: std.Io,
        tool_name: []const u8,
        args_json: []const u8,
    ) ClientError![]const u8 {
        const payload = try std.fmt.allocPrint(allocator,
            \\{{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{{"name":"{s}","arguments":{s}}}}}
        , .{ tool_name, args_json });
        defer allocator.free(payload);

        const script = try std.fmt.allocPrint(allocator,
            "echo '{s}' | {s}",
            .{ payload, self.cmd },
        );
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

    pub fn listTools(
        self: *const Client,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) ClientError![]const u8 {
        const payload = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}";
        const script = try std.fmt.allocPrint(allocator, "echo '{s}' | {s}", .{ payload, self.cmd });
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

/// Stub response when TARS_MCP_CMD is unset.
pub fn stubCall(allocator: std.mem.Allocator, tool_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{{\"tool\":\"{s}\",\"status\":\"mcp_stub\",\"note\":\"set TARS_MCP_CMD\"}}", .{tool_name});
}
