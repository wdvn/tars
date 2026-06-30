//! Operational metrics — registry, collector, report, persist.

const std = @import("std");

pub const registry = @import("registry.zig");
pub const collector = @import("collector.zig");
pub const report = @import("report.zig");
pub const persist = @import("persist.zig");

pub const Metrics = collector.Metrics;
pub const gInc = collector.gInc;
pub const gIncTags = collector.gIncTags;
pub const gGauge = collector.gGauge;
pub const setGlobal = collector.setGlobal;
pub const global = collector.global;

/// Wrap LLM provider to record latency, tokens, and stream chunk metrics.
pub fn instrumentProvider(m: *Metrics, io: std.Io, provider: @import("../llm/mod.zig").Provider) @import("../llm/mod.zig").Provider {
    return @import("instrument.zig").wrap(m, io, provider);
}
