const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");

const output_schema =
    \\{"type":"object","properties":{"steps":{"type":"array","items":{"type":"string"}},"rollback":{"type":"string"},"contingencies":{"type":"array","items":{"type":"string"}}},"required":["steps","rollback","contingencies"]}
;

const system_prompt =
    \\You are the TARS Planner (Analyst Agent). Produce a minimal correct plan.
    \\Include Plan A steps, rollback path, and contingencies. Output strict JSON only.
;

pub fn block() rb.Block {
    return .{
        .id = "planner",
        .phase = .plan,
        .ptr = @ptrCast(@constCast(&state)),
        .invokeFn = invoke,
    };
}

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
        .config = .{ .temperature = 0.2 },
        .system = system_prompt,
        .messages = &.{
            .{ .role = "user", .content = prompt },
        },
        .output_schema = output_schema,
    }) catch return types.BlockError.LlmFailed;
    defer allocator.free(response.content_json);

    const payload = allocator.dupe(u8, response.content_json) catch return types.BlockError.InvalidInput;
    return .{ .kind = "plan", .payload_json = payload };
}

var state: u8 = 0;
