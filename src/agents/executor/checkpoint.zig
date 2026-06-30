//! Per-step backup and rollback for Executor — enables retry after failure.

const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("../../memory/mod.zig");
const metrics = @import("../../metrics/collector.zig");

pub const CheckpointError = error{
    BackupFailed,
    RollbackFailed,
    StorageUnavailable,
    OutOfMemory,
};

const backup_root: []const u8 = ".tars/backups";

/// Options for resume/retry after a partial run.
pub const ExecuteOptions = struct {
    from_step: usize = 0,
    /// When true and `from_step` is set, restore that step's backup before re-running.
    rollback_before_retry: bool = false,
    repo_root: []const u8 = ".",
};

/// Create filesystem backup + pending checkpoint row before running a step.
pub fn prepareStep(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: memory.store.Store,
    mission_id: []const u8,
    step_index: usize,
    step: types.ActionStep,
    repo_root: []const u8,
    created_at: i64,
) CheckpointError![]const u8 {
    const safe_mid = try sanitizeId(allocator, mission_id);
    defer allocator.free(safe_mid);

    const backup_dir = try std.fmt.allocPrint(allocator, "{s}/{s}/step_{d:0>4}", .{
        backup_root, safe_mid, step_index,
    });
    errdefer allocator.free(backup_dir);

    const meta = try buildBackupMeta(allocator, io, step, backup_dir, repo_root);
    defer allocator.free(meta);

    const mkdir_cmd = try std.fmt.allocPrint(allocator, "mkdir -p '{s}'", .{backup_dir});
    defer allocator.free(mkdir_cmd);
    try runShell(io, allocator, mkdir_cmd);

    store.upsertExecutorCheckpoint(
        io,
        mission_id,
        step_index,
        step.kind.name(),
        step.payload,
        backup_dir,
        meta,
        created_at,
    ) catch return CheckpointError.StorageUnavailable;

    metrics.gInc("executor.checkpoints.prepared", 1);
    return backup_dir;
}

/// Record step outcome on the checkpoint row.
pub fn completeStep(
    io: std.Io,
    store: memory.store.Store,
    mission_id: []const u8,
    step_index: usize,
    success: bool,
    result_json: []const u8,
) CheckpointError!void {
    const status = if (success) "completed" else "failed";
    store.finishExecutorCheckpoint(io, mission_id, step_index, status, result_json) catch {
        return CheckpointError.StorageUnavailable;
    };
}

/// Restore filesystem/git state from a step checkpoint (best-effort undo).
pub fn rollbackStep(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: memory.store.Store,
    mission_id: []const u8,
    step_index: usize,
    repo_root: []const u8,
) CheckpointError!void {
    const meta_json = store.queryExecutorCheckpointMeta(io, mission_id, step_index) catch {
        return CheckpointError.StorageUnavailable;
    };
    defer store.allocator.free(meta_json);
    if (std.mem.trim(u8, meta_json, " \r\n").len == 0) return;

    if (std.mem.indexOf(u8, meta_json, "\"target_path\"") != null) {
        try restoreFileEdit(allocator, io, meta_json, repo_root);
    }
    if (std.mem.indexOf(u8, meta_json, "\"pre_head\"") != null and
        std.mem.indexOf(u8, meta_json, "\"mutating\":true") != null)
    {
        try restoreGitHead(allocator, io, meta_json, repo_root);
    }

    store.markExecutorCheckpointRolledBack(io, mission_id, step_index) catch {
        return CheckpointError.StorageUnavailable;
    };
    metrics.gInc("executor.checkpoints.restored", 1);
}

fn buildBackupMeta(
    allocator: std.mem.Allocator,
    io: std.Io,
    step: types.ActionStep,
    backup_dir: []const u8,
    repo_root: []const u8,
) ![]const u8 {
    return switch (step.kind) {
        .file_edit => try backupFileEdit(allocator, io, step.payload, backup_dir, repo_root),
        .git => try backupGitState(allocator, io, step.payload, repo_root),
        else => try std.fmt.allocPrint(allocator, "{{\"kind\":\"{s}\",\"backup_dir\":\"{s}\",\"note\":\"metadata_only\"}}", .{ step.kind.name(), backup_dir }),
    };
}

fn backupFileEdit(
    allocator: std.mem.Allocator,
    io: std.Io,
    rel_path: []const u8,
    backup_dir: []const u8,
    repo_root: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, rel_path, "..") != null) {
        return std.fmt.allocPrint(allocator, "{{\"target_path\":\"{s}\",\"error\":\"path_escape\"}}", .{rel_path});
    }

    const src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repo_root, rel_path });
    defer allocator.free(src);
    const dst = try std.fmt.allocPrint(allocator, "{s}/file.bak", .{backup_dir});
    defer allocator.free(dst);

    const cmd = try std.fmt.allocPrint(allocator, "test -f '{s}' && cp -- '{s}' '{s}' || true", .{ src, src, dst });
    defer allocator.free(cmd);
    try runShell(io, allocator, cmd);

    const existed_cmd = try std.fmt.allocPrint(allocator, "test -f '{s}' && echo yes || echo no", .{src});
    defer allocator.free(existed_cmd);
    const existed_out = runShellCapture(allocator, io, existed_cmd) catch try allocator.dupe(u8, "no");
    defer allocator.free(existed_out);
    const existed = std.mem.indexOf(u8, existed_out, "yes") != null;

    return std.fmt.allocPrint(allocator,
        \\{{"target_path":"{s}","backup_file":"{s}/file.bak","backup_dir":"{s}","existed":{s}}}
    , .{ rel_path, backup_dir, backup_dir, if (existed) "true" else "false" });
}

fn backupGitState(
    allocator: std.mem.Allocator,
    io: std.Io,
    subcommand: []const u8,
    repo_root: []const u8,
) ![]const u8 {
    const head_cmd = try std.fmt.allocPrint(allocator, "cd '{s}' && git rev-parse HEAD 2>/dev/null || echo ''", .{repo_root});
    defer allocator.free(head_cmd);
    const head = runShellCapture(allocator, io, head_cmd) catch try allocator.dupe(u8, "");
    defer allocator.free(head);
    const trimmed = std.mem.trim(u8, head, " \r\n");

    const mutating = isMutatingGit(subcommand);
    return std.fmt.allocPrint(allocator,
        \\{{"pre_head":"{s}","mutating":{s},"subcommand":"{s}","note":"git_snapshot"}}
    , .{ trimmed, if (mutating) "true" else "false", subcommand });
}

fn restoreFileEdit(
    allocator: std.mem.Allocator,
    io: std.Io,
    meta_json: []const u8,
    repo_root: []const u8,
) CheckpointError!void {
    const target = extractJsonString(meta_json, "target_path") orelse return;
    const backup_file = extractJsonString(meta_json, "backup_file") orelse return;
    const existed = std.mem.indexOf(u8, meta_json, "\"existed\":true") != null;

    const full_target = std.fmt.allocPrint(allocator, "{s}/{s}", .{ repo_root, target }) catch return CheckpointError.OutOfMemory;
    defer allocator.free(full_target);

    if (existed) {
        const cmd = std.fmt.allocPrint(allocator, "cp -- '{s}' '{s}'", .{ backup_file, full_target }) catch return CheckpointError.OutOfMemory;
        defer allocator.free(cmd);
        try runShell(io, allocator, cmd);
    } else {
        const cmd = std.fmt.allocPrint(allocator, "rm -f '{s}'", .{full_target}) catch return CheckpointError.OutOfMemory;
        defer allocator.free(cmd);
        try runShell(io, allocator, cmd);
    }
}

fn restoreGitHead(
    allocator: std.mem.Allocator,
    io: std.Io,
    meta_json: []const u8,
    repo_root: []const u8,
) CheckpointError!void {
    const pre_head = extractJsonString(meta_json, "pre_head") orelse return;
    if (pre_head.len == 0) return;

    const cmd = std.fmt.allocPrint(allocator, "cd '{s}' && git reset --hard '{s}'", .{ repo_root, pre_head }) catch return CheckpointError.OutOfMemory;
    defer allocator.free(cmd);
    try runShell(io, allocator, cmd);
}

fn isMutatingGit(subcommand: []const u8) bool {
    const verbs = [_][]const u8{ "commit", "merge", "rebase", "reset", "checkout", "apply", "cherry-pick", "push", "stash", "add", "rm", "mv", "clean" };
    for (verbs) |verb| {
        if (std.mem.startsWith(u8, subcommand, verb)) return true;
        var i: usize = 0;
        while (i < subcommand.len) : (i += 1) {
            if (subcommand[i] == ' ' and i + 1 + verb.len <= subcommand.len and
                std.mem.startsWith(u8, subcommand[i + 1 ..], verb))
                return true;
        }
    }
    return false;
}

fn sanitizeId(allocator: std.mem.Allocator, mission_id: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (mission_id) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_';
        try out.append(allocator, if (ok) c else '_');
    }
    return out.toOwnedSlice(allocator);
}

fn runShell(io: std.Io, allocator: std.mem.Allocator, cmd: []const u8) CheckpointError!void {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    }) catch return CheckpointError.BackupFailed;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    switch (result.term) {
        .exited => |code| if (code != 0) return CheckpointError.BackupFailed,
        else => return CheckpointError.BackupFailed,
    }
}

fn runShellCapture(allocator: std.mem.Allocator, io: std.Io, cmd: []const u8) ![]const u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    });
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return error.ShellFailed;
        },
        else => {
            allocator.free(result.stdout);
            return error.ShellFailed;
        },
    }
    return result.stdout;
}

/// Minimal JSON string extractor for flat checkpoint meta (no nested objects).
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    var buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&buf, "\"{s}\":\"", .{key}) catch return null;
    const start = std.mem.indexOf(u8, json, needle) orelse return null;
    const value_start = start + needle.len;
    const end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;
    return json[value_start..end];
}
