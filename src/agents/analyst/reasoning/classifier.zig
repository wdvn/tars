const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");
const invoke_llm = @import("invoke_llm.zig");

const output_schema =
    \\{"type":"object","properties":{"type":{"type":"string"},"severity":{"type":"string"},"hypothesis":{"type":"array","items":{"type":"string"}}},"required":["type","severity","hypothesis"]}
;

const orient_system_prompt =
    \\You are the TARS Classifier (Analyst Agent). Distinguish symptom from root cause.
    \\Be honest (honesty parameter 90%). Output strict JSON only.
;

const assess_system_prompt =
    \\You are the TARS Classifier (Analyst Agent). Re-evaluate symptom vs root cause with new evidence.
    \\Update severity and hypothesis if ASSESS findings change the picture. Output strict JSON only.
;

/// Register ORIENT-phase classifier block (symptom vs root cause).
pub fn blockOrient() rb.Block {
    return .{
        .id = "classifier",
        .phase = .orient,
        .ptr = @ptrCast(@constCast(&orient_state)),
        .invokeFn = invokeOrient,
    };
}

/// Register ASSESS-phase classifier block (re-classify after new evidence).
pub fn blockAssess() rb.Block {
    return .{
        .id = "classifier_reassess",
        .phase = .assess,
        .ptr = @ptrCast(@constCast(&assess_state)),
        .invokeFn = invokeAssess,
    };
}

fn invokeOrient(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
) types.BlockError!types.BlockResult {
    _ = ptr;
    return invoke_llm.completeJson(allocator, provider, ctx, orient_system_prompt, output_schema, "classification", 0.3);
}

fn invokeAssess(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
) types.BlockError!types.BlockResult {
    _ = ptr;
    return invoke_llm.completeJson(allocator, provider, ctx, assess_system_prompt, output_schema, "classification", 0.2);
}

var orient_state: u8 = 0;
var assess_state: u8 = 0;
