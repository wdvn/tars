//! Public library root — re-exports all TARS subsystems for `@import("tars")`.

pub const types = @import("types.zig");
pub const llm = @import("llm/mod.zig");
pub const memory = @import("memory/mod.zig");
pub const policy = @import("policy/mod.zig");
pub const agents = @import("agents/mod.zig");
pub const stream = @import("stream/mod.zig");
pub const perception = @import("perception/mod.zig");
pub const mcp = @import("mcp/mod.zig");
pub const session = @import("session/mod.zig");
pub const skills = @import("skills/mod.zig");
pub const core = @import("core/mod.zig");
pub const metrics = @import("metrics/mod.zig");

pub const analyst = agents.analyst;
pub const executor = agents.executor;
pub const monitor = agents.monitor;
