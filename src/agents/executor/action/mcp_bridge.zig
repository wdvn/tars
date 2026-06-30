const std = @import("std");
const types = @import("../../../types.zig");
const action = @import("block.zig");
const mcp = @import("../../../mcp/mod.zig");
const metrics = @import("../../../metrics/collector.zig");

/// MCP bridge — calls external MCP server when TARS_MCP_CMD is set.
pub fn block() action.Block {
    return .{
        .id = "mcp_bridge",
        .kind = .mcp,
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    act: types.Action,
) types.ExecutorError!types.ActionResult {
    _ = ptr;
    metrics.gInc("mcp.tool.calls", 1);

    const payload = if (std.mem.indexOf(u8, act.payload, ":")) |colon| blk: {
        const tool = act.payload[0..colon];
        const args = std.mem.trim(u8, act.payload[colon + 1 ..], " ");
        break :blk .{ tool, args };
    } else .{ act.payload, "{}" };

    const stdout = if (mcp.client.Client.fromEnv(allocator, io)) |client| blk: {
        defer client.deinit();
        break :blk mcp.client.Client.callTool(&client, allocator, io, payload[0], payload[1]) catch {
            metrics.gInc("mcp.tool.errors", 1);
            break :blk try mcp.client.stubCall(allocator, payload[0]);
        };
    } else try mcp.client.stubCall(allocator, payload[0]);

    return .{
        .step_index = 0,
        .kind = .mcp,
        .success = true,
        .stdout = stdout,
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

var state: u8 = 0;
