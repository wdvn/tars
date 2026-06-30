//! Shared types: agents, phases, mission context.

pub const Agent = enum {
    analyst,
    executor,
    monitor,

    pub fn name(self: Agent) []const u8 {
        return switch (self) {
            .analyst => "analyst",
            .executor => "executor",
            .monitor => "monitor",
        };
    }
};

pub const Phase = enum {
    orient,
    assess,
    plan,
    act,
    verify,

    pub fn name(self: Phase) []const u8 {
        return switch (self) {
            .orient => "orient",
            .assess => "assess",
            .plan => "plan",
            .act => "act",
            .verify => "verify",
        };
    }
};

pub const MissionStatus = enum {
    orient,
    assess,
    plan,
    act,
    verify,
    done,
    blocked,

    pub fn name(self: MissionStatus) []const u8 {
        return @tagName(self);
    }
};

pub const Priority = enum {
    critical,
    normal,
    background,

    pub fn name(self: Priority) []const u8 {
        return @tagName(self);
    }
};

pub const MissionContext = struct {
    mission_id: []const u8,
    goal: []const u8,
    phase: Phase,
    status: MissionStatus,
    priority: Priority,
    /// JSON blob — perception / recall evidence for reasoning blocks
    evidence: []const u8,
};

pub const BlockError = error{
    InvalidInput,
    LlmFailed,
    SchemaViolation,
    StorageUnavailable,
};

pub const BlockResult = struct {
    kind: []const u8,
    payload_json: []const u8,
};

/// Single executable step from an approved plan (Analyst → Executor).
pub const ActionStep = struct {
    kind: ActionKind,
    /// shell: command · file_edit: path · git: subcommand · verify: command
    payload: []const u8,
};

pub const ActionKind = enum {
    shell,
    file_edit,
    git,
    verify,
    mcp,

    pub fn name(self: ActionKind) []const u8 {
        return @tagName(self);
    }
};

pub const Action = struct {
    kind: ActionKind,
    payload: []const u8,
};

pub const ApprovedPlan = struct {
    mission_id: []const u8,
    steps: []const ActionStep,
    rollback: []const u8 = "",
};

pub const ActionResult = struct {
    step_index: usize,
    kind: ActionKind,
    success: bool,
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
};

pub const BlockedAction = struct {
    step_index: usize,
    boundary: []const u8,
    reason: []const u8,
    alternative: []const u8,
};

pub const ExecuteOutcome = union(enum) {
    completed: []const ActionResult,
    blocked: struct {
        completed: []const ActionResult,
        blocked: BlockedAction,
    },
};

pub const VerifyOutcome = union(enum) {
    pass: Handoff,
    fail: LoopBack,
};

pub const Handoff = struct {
    summary_json: []const u8,
};

pub const LoopBack = struct {
    target_phase: Phase,
    reason: []const u8,
    detail_json: []const u8,
};

pub const ExecutorError = error{
    ActionFailed,
    StorageUnavailable,
    InvalidPlan,
    OutOfMemory,
};

pub const MonitorError = error{
    VerifyFailed,
    StorageUnavailable,
    OutOfMemory,
};
