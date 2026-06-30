const types = @import("../../../types.zig");

pub const Watchdog = struct {
    failure_streak: u32 = 0,

    pub fn recordFailure(self: *Watchdog) bool {
        self.failure_streak += 1;
        return self.failure_streak >= 3;
    }

    pub fn recordSuccess(self: *Watchdog) void {
        self.failure_streak = 0;
    }

    pub fn shouldEscalateToOperator(self: *const Watchdog) bool {
        return self.failure_streak >= 3;
    }

    pub fn loopBackPhase(self: *const Watchdog) types.Phase {
        _ = self;
        return .assess;
    }
};
