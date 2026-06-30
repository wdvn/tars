//! Analyst Agent — ORIENT · ASSESS · PLAN

const std = @import("std");
const types = @import("../../types.zig");
const llm = @import("../../llm/mod.zig");
const memory = @import("../../memory/mod.zig");
const reasoning = @import("reasoning/mod.zig");
const metrics = @import("../../metrics/collector.zig");

pub const Analyst = struct {
    store: memory.store.Store,
    provider: llm.Provider,
    io: std.Io,

    /// Bind store, LLM provider, and I/O for one Analyst agent instance.
    pub fn init(store: memory.store.Store, provider: llm.Provider, io: std.Io) Analyst {
        return .{ .store = store, .provider = provider, .io = io };
    }

    pub fn runPhase(
        self: *const Analyst,
        allocator: std.mem.Allocator,
        ctx: *const types.MissionContext,
    ) ![]types.BlockResult {
        // Invoke every reasoning block registered for the current mission phase.
        const registry = reasoning.allBlocks();
        var results: std.ArrayList(types.BlockResult) = .empty;
        errdefer {
            for (results.items) |r| allocator.free(r.payload_json);
            results.deinit(allocator);
        }

        const now: i64 = 0; // TODO: wall clock when std.time API is wired for Zig 0.16

        for (registry) |b| {
            if (b.phase != ctx.phase) continue;
            const result = try b.invoke(allocator, self.provider, ctx);
            try results.append(allocator, result);
            metrics.gInc("analyst.blocks.invoked", 1);

            try self.store.writeArtifact(
                self.io,
                ctx.mission_id,
                ctx.phase.name(),
                types.Agent.analyst.name(),
                result.kind,
                result.payload_json,
                now,
            );
            metrics.gInc("analyst.artifacts.written", 1);
        }

        if (ctx.phase == .plan) {
            // Executor expects the planner artifact, not trade_off (last block in PLAN phase).
            for (results.items) |r| {
                if (std.mem.eql(u8, r.kind, "plan")) {
                    try self.store.publishBusEvent(
                        self.io,
                        ctx.mission_id,
                        "analyst",
                        "executor",
                        "plan_ready",
                        r.payload_json,
                        now,
                    );
                    metrics.gInc("bus.events.published", 1);
                    break;
                }
            }
        }

        return results.toOwnedSlice(allocator);
    }

    /// Path to external vector recall SQL (used when sqlite-vector is loaded).
    pub fn orientRecallQuery(_: *const Analyst) []const u8 {
        return memory.store.query_recall_path;
    }
};
