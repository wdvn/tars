const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");

const output_schema =
    \\{"type":"object","properties":{"options":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"cost":{"type":"array","items":{"type":"string"}},"benefit":{"type":"array","items":{"type":"string"}}},"required":["name","cost","benefit"]}}},"required":["options"]}
;

const system_prompt =
    \\You are the TARS Trade-off Resolver (Analyst Agent). When constraints conflict, rank options.
    \\Encode necessary sacrifice (hotfix vs deep fix, scope vs deadline). Output strict JSON only.
;

/// Register PLAN-phase trade-off block (rank conflicting options).
pub fn block() rb.Block {
    return .{
        .id = "trade_off",
        .phase = .plan,
        .ptr = @ptrCast(@constCast(&state)),
        .invokeFn = invoke,
    };
}

/// Resolve constraint conflicts into ranked options with cost/benefit arrays.
fn invoke(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
) types.BlockError!types.BlockResult {
    _ = ptr;
    const prompt = rb.assemblePrompt(allocator, system_prompt, ctx, output_schema) catch return types.BlockError.InvalidInput;
    defer allocator.free(prompt);

    const response = provider.complete(allocator, .{
        .config = .{ .temperature = 0.15 },
        .system = system_prompt,
        .messages = &.{
            .{ .role = "user", .content = prompt },
        },
        .output_schema = output_schema,
    }) catch return types.BlockError.LlmFailed;
    defer allocator.free(response.content_json);

    const payload = allocator.dupe(u8, response.content_json) catch return types.BlockError.InvalidInput;
    return .{ .kind = "trade_off", .payload_json = payload };
}

var state: u8 = 0;
