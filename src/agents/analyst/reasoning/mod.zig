const block = @import("block.zig");
const classifier = @import("classifier.zig");
const planner = @import("planner.zig");
const risk_assessor = @import("risk_assessor.zig");
const trade_off = @import("trade_off.zig");

pub const Block = block.Block;
pub const assemblePrompt = block.assemblePrompt;
pub const blocksForPhase = block.blocksForPhase;

pub fn allBlocks() [4]Block {
    return .{
        classifier.block(),
        risk_assessor.block(),
        planner.block(),
        trade_off.block(),
    };
}
