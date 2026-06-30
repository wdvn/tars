const types = @import("../../../types.zig");

pub const Watchdog = struct {
    failure_streak: u32 = 0,

    /// Increment failure streak; return true when threshold triggers escalation.
    pub fn recordFailure(self: *Watchdog) bool {
        self.failure_streak += 1;
        return self.failure_streak >= 3;
    }

    /// Reset streak after successful verify — prevents transient flake escalation.
    pub fn recordSuccess(self: *Watchdog) void {
        self.failure_streak = 0;
    }

    /// Three consecutive failures → operator escalation (loop-back still allowed).
    pub fn shouldEscalateToOperator(self: *const Watchdog) bool {
        return self.failure_streak >= 3;
    }

    /// Target phase for Monitor loop-back after repeated verify failures.
    pub fn loopBackPhase(self: *const Watchdog) types.Phase {
        _ = self;
        return .assess;
    }
};
