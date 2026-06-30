const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");

const output_schema =
    \\{"type":"object","properties":{"type":{"type":"string"},"severity":{"type":"string"},"hypothesis":{"type":"array","items":{"type":"string"}}},"required":["type","severity","hypothesis"]}
;

const system_prompt =
    \\You are the TARS Classifier (Analyst Agent). Distinguish symptom from root cause.
    \\Be honest (honesty parameter 90%). Output strict JSON only.
;

pub fn block() rb.Block {
    return .{
        .id = "classifier",
        .phase = .orient,
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
        .config = .{},
        .system = system_prompt,
        .messages = &.{
            .{ .role = "user", .content = prompt },
        },
        .output_schema = output_schema,
    }) catch return types.BlockError.LlmFailed;
    defer allocator.free(response.content_json);

    const payload = allocator.dupe(u8, response.content_json) catch return types.BlockError.InvalidInput;
    return .{ .kind = "classification", .payload_json = payload };
}

var state: u8 = 0;
