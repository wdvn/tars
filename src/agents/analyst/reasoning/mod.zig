const types = @import("../../../types.zig");
const block = @import("block.zig");
const classifier = @import("classifier.zig");
const planner = @import("planner.zig");
const risk_assessor = @import("risk_assessor.zig");
const trade_off = @import("trade_off.zig");

pub const Block = block.Block;
pub const assemblePrompt = block.assemblePrompt;
pub const assembleUserPrompt = block.assembleUserPrompt;

/// Return all Analyst reasoning blocks in OODA order for full-phase runs.
pub fn allBlocks() [5]Block {
    return .{
        classifier.blockOrient(),
        classifier.blockAssess(),
        risk_assessor.block(),
        planner.block(),
        trade_off.block(),
    };
}

/// Copy blocks matching `phase` into `buf`; returns the used prefix of `buf`.
pub fn blocksForPhase(phase: types.Phase, buf: []Block) []Block {
    const all = allBlocks();
    var n: usize = 0;
    for (all) |b| {
        if (b.phase == phase and n < buf.len) {
            buf[n] = b;
            n += 1;
        }
    }
    return buf[0..n];
}
