//! Shared LLM invocation for Analyst reasoning blocks.

const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");

/// Non-stream completion with runtime max_tokens and structured JSON output.
pub fn completeJson(
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
    system_prompt: []const u8,
    output_schema: []const u8,
    kind: []const u8,
    temperature: f32,
) types.BlockError!types.BlockResult {
    const prompt = rb.assembleUserPrompt(allocator, ctx, output_schema) catch return types.BlockError.InvalidInput;
    defer allocator.free(prompt);

    const max_tokens: u32 = if (llm.runtimeConfig()) |rc| rc.max_tokens else 4096;

    const response = provider.complete(allocator, .{
        .config = .{ .temperature = temperature, .max_tokens = max_tokens },
        .system = system_prompt,
        .messages = &.{.{ .role = "user", .content = prompt }},
        .output_schema = output_schema,
    }) catch return types.BlockError.LlmFailed;
    defer allocator.free(response.content_json);

    const payload = allocator.dupe(u8, response.content_json) catch return types.BlockError.InvalidInput;
    return .{ .kind = kind, .payload_json = payload };
}
