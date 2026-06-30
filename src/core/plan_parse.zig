//! Parse Analyst planner JSON into an Executor-ready ApprovedPlan.

const std = @import("std");
const types = @import("../types.zig");
const plan_mod = @import("plan.zig");
const memory = @import("../memory/mod.zig");

pub const ParseError = error{
    OutOfMemory,
    InvalidPlan,
};

pub const OwnedPlan = struct {
    mission_id: []const u8,
    steps: []types.ActionStep,
    step_payloads: [][]const u8,
    rollback: []const u8,

    pub fn deinit(self: *OwnedPlan, allocator: std.mem.Allocator) void {
        for (self.step_payloads) |p| allocator.free(p);
        allocator.free(self.step_payloads);
        allocator.free(self.steps);
        allocator.free(self.rollback);
        allocator.free(self.mission_id);
        self.* = undefined;
    }

    pub fn asApproved(self: *const OwnedPlan) types.ApprovedPlan {
        return .{
            .mission_id = self.mission_id,
            .steps = self.steps,
            .rollback = self.rollback,
        };
    }
};

/// Build plan from planner block JSON payload.
pub fn fromPlannerJson(
    allocator: std.mem.Allocator,
    mission_id: []const u8,
    plan_json: []const u8,
) ParseError!OwnedPlan {
    const steps_raw = extractStringArray(allocator, plan_json, "steps") catch return error.InvalidPlan;
    defer {
        for (steps_raw) |s| allocator.free(s);
        allocator.free(steps_raw);
    }

    var payloads: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (payloads.items) |p| allocator.free(p);
        payloads.deinit(allocator);
    }
    var steps: std.ArrayList(types.ActionStep) = .empty;
    errdefer steps.deinit(allocator);

    for (steps_raw) |step_str| {
        const mapped = try mapStep(allocator, step_str);
        try payloads.append(allocator, mapped.payload);
        try steps.append(allocator, .{ .kind = mapped.kind, .payload = mapped.payload });
    }

    const rollback = plan_mod.extractRollbackField(allocator, plan_json) catch null;
    errdefer if (rollback) |r| allocator.free(r);

    return .{
        .mission_id = try allocator.dupe(u8, mission_id),
        .steps = try steps.toOwnedSlice(allocator),
        .step_payloads = try payloads.toOwnedSlice(allocator),
        .rollback = rollback orelse try allocator.dupe(u8, ""),
    };
}

/// Load latest Analyst `plan` artifact from SQLite.
pub fn fromLatestArtifact(
    allocator: std.mem.Allocator,
    store: memory.store.Store,
    io: std.Io,
    mission_id: []const u8,
) ParseError!OwnedPlan {
    const payload = store.queryLatestArtifactPayload(io, mission_id, "plan") catch return error.InvalidPlan;
    defer store.allocator.free(payload);
    if (std.mem.trim(u8, payload, " \r\n").len == 0) return error.InvalidPlan;
    return fromPlannerJson(allocator, mission_id, payload);
}

const MappedStep = struct {
    kind: types.ActionKind,
    payload: []const u8,
};

fn mapStep(allocator: std.mem.Allocator, raw: []const u8) ParseError!MappedStep {
    const step = std.mem.trim(u8, raw, " \r\n");
    if (step.len == 0) return error.InvalidPlan;

    if (std.mem.startsWith(u8, step, "mcp:")) {
        return .{ .kind = .mcp, .payload = try dupPayload(allocator, step["mcp:".len..]) };
    }
    if (std.mem.startsWith(u8, step, "skill:")) {
        return .{ .kind = .skill, .payload = try dupPayload(allocator, step["skill:".len..]) };
    }
    if (std.mem.startsWith(u8, step, "git:")) {
        return .{ .kind = .git, .payload = try dupPayload(allocator, step["git:".len..]) };
    }
    if (std.mem.startsWith(u8, step, "grep:")) {
        const pattern = std.mem.trim(u8, step["grep:".len..], " ");
        const cmd = try std.fmt.allocPrint(allocator, "rg -m 8 -- {s} . 2>/dev/null || grep -r -m 8 -- {s} . 2>/dev/null || true", .{ pattern, pattern });
        return .{ .kind = .shell, .payload = cmd };
    }
    if (std.mem.startsWith(u8, step, "shell:")) {
        return .{ .kind = .shell, .payload = try dupPayload(allocator, step["shell:".len..]) };
    }
    return .{ .kind = .shell, .payload = try dupPayload(allocator, step) };
}

fn dupPayload(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = std.mem.trim(u8, text, " ");
    return allocator.dupe(u8, trimmed) catch return error.OutOfMemory;
}

/// Extract JSON string values from `"key":[ "a", "b" ]` without a full parser.
fn extractStringArray(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![][]const u8 {
    const needle = try std.fmt.allocPrint(allocator, "\"{s}\":", .{key});
    defer allocator.free(needle);

    const trimmed = std.mem.trim(u8, json, " \r\n");
    const key_pos = std.mem.indexOf(u8, trimmed, needle) orelse return error.InvalidPlan;
    const after_key = trimmed[key_pos + needle.len ..];
    const arr_start = std.mem.indexOf(u8, after_key, "[") orelse return error.InvalidPlan;
    const arr_body = after_key[arr_start + 1 ..];
    const arr_end = std.mem.indexOf(u8, arr_body, "]") orelse return error.InvalidPlan;
    const inner = arr_body[0..arr_end];

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |s| allocator.free(s);
        out.deinit(allocator);
    }

    var i: usize = 0;
    while (i < inner.len) {
        const q = std.mem.indexOfScalar(u8, inner[i..], '"') orelse break;
        const start = i + q + 1;
        var j = start;
        while (j < inner.len) : (j += 1) {
            if (inner[j] == '\\' and j + 1 < inner.len) {
                j += 1;
                continue;
            }
            if (inner[j] == '"') break;
        }
        if (j >= inner.len) break;
        const slice = inner[start..j];
        const unescaped = try unescapeJsonString(allocator, slice);
        try out.append(allocator, unescaped);
        i = j + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn unescapeJsonString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\' and i + 1 < text.len) {
            const next = text[i + 1];
            try buf.append(allocator, switch (next) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '"', '\\' => next,
                else => next,
            });
            i += 1;
        } else {
            try buf.append(allocator, text[i]);
        }
    }
    return buf.toOwnedSlice(allocator);
}
