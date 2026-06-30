//! Safety Guard — P5 hard boundaries before Executor actions.

const std = @import("std");
const types = @import("../types.zig");
const metrics = @import("../metrics/collector.zig");

pub const Verdict = union(enum) {
    allow,
    deny: DenyReason,
};

pub const DenyReason = struct {
    boundary: []const u8,
    reason: []const u8,
    alternative: []const u8,
};

pub const Guard = struct {
    /// Gate action through P5 boundaries; increment denial metric on reject.
    pub fn evaluate(action: types.Action) Verdict {
        metrics.gInc("safety.guard.evaluations", 1);
        const verdict = evaluateInner(action);
        switch (verdict) {
            .deny => metrics.gInc("safety.guard.denials", 1),
            .allow => {},
        }
        return verdict;
    }

    /// Route by action kind — verify is read-only; MCP rules deferred.
    fn evaluateInner(action: types.Action) Verdict {
        switch (action.kind) {
            .shell => return evaluateShell(action.payload),
            .file_edit => return evaluateFileEdit(action.payload),
            .git => return evaluateGit(action.payload),
            .verify => return .allow, // read-only by design
            .mcp => return .allow, // MCP JSON-RPC tools via TARS_MCP_CMD
            .skill => return .allow, // read-only SKILL.md load
        }
    }

    /// Pattern-match shell command (lowercased) against irreversible/destructive signatures.
    fn evaluateShell(command: []const u8) Verdict {
        const lower = std.ascii.allocLowerString(std.heap.page_allocator, command) catch command;
        defer if (lower.ptr != command.ptr) std.heap.page_allocator.free(lower);

        const hay = if (lower.ptr == command.ptr) command else lower;

        if (containsAny(hay, &.{
            "rm -rf /",
            "rm -rf /*",
            "mkfs.",
            ":(){ :|:& };:",
        })) {
            return deny(
                "irreversible_data_destruction",
                "command may destroy system data",
                "scope deletion to a specific project path",
            );
        }

        if (containsAny(hay, &.{
            "git push --force",
            "git push -f ",
            "push --force origin main",
            "push --force origin master",
        })) {
            return deny(
                "irreversible_data_destruction",
                "force push to main/master is forbidden",
                "use a feature branch and open a PR",
            );
        }

        if (containsAny(hay, &.{
            "--no-verify",
            "skip hooks",
            "HUSKY=0",
        })) {
            return deny(
                "security_bypass",
                "skipping git hooks is forbidden",
                "fix hook failures or ask operator to override explicitly",
            );
        }

        if (containsAny(hay, &.{
            "git add .env",
            "git add -f .env",
            "credentials.json",
            "id_rsa",
        })) {
            return deny(
                "security_bypass",
                "adding secrets to version control is forbidden",
                "add path to .gitignore and rotate exposed secrets",
            );
        }

        return .allow;
    }

    /// Block edits touching .env unless explicitly gitignore-related.
    fn evaluateFileEdit(payload: []const u8) Verdict {
        if (std.mem.indexOf(u8, payload, ".env") != null and
            std.mem.indexOf(u8, payload, "gitignore") == null)
        {
            return deny(
                "security_bypass",
                "editing .env may expose secrets",
                "use environment variables or a secrets manager",
            );
        }
        return .allow;
    }

    /// Deny force-push and unsolicited commits (operator must approve commits).
    fn evaluateGit(subcommand: []const u8) Verdict {
        if (std.mem.startsWith(u8, subcommand, "push") and
            (std.mem.indexOf(u8, subcommand, "--force") != null or std.mem.indexOf(u8, subcommand, " -f") != null))
        {
            return deny(
                "irreversible_data_destruction",
                "force push is forbidden by default",
                "push to a non-protected branch",
            );
        }
        if (std.mem.eql(u8, subcommand, "commit")) {
            return deny(
                "obedience_boundary",
                "git commit requires explicit operator request",
                "pass approved=true in plan metadata",
            );
        }
        return .allow;
    }

    /// Substring scan for any forbidden needle in command text.
    fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
        for (needles) |n| {
            if (std.mem.indexOf(u8, haystack, n) != null) return true;
        }
        return false;
    }

    /// Construct deny verdict with boundary id, reason, and suggested alternative.
    fn deny(boundary: []const u8, reason: []const u8, alternative: []const u8) Verdict {
        return .{ .deny = .{
            .boundary = boundary,
            .reason = reason,
            .alternative = alternative,
        } };
    }
};
