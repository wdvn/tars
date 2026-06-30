//! Skill discovery — load SKILL.md from configured directories (Cursor-style layout).

const std = @import("std");
const env = @import("../llm/env.zig");

pub const SkillError = error{
    NotFound,
    IoFailed,
    OutOfMemory,
};

pub const SkillInfo = struct {
    name: []const u8,
    path: []const u8,
};

/// Default search roots when TARS_SKILLS_DIR is unset.
pub fn defaultDirs(allocator: std.mem.Allocator) ![]const []const u8 {
    var dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (dirs.items) |d| allocator.free(d);
        dirs.deinit(allocator);
    }
    try dirs.append(allocator, try allocator.dupe(u8, "skills"));
    try dirs.append(allocator, try allocator.dupe(u8, ".cursor/skills-cursor"));
    return dirs.toOwnedSlice(allocator);
}

/// Colon-separated paths from TARS_SKILLS_DIR, else built-in defaults.
pub fn searchDirs(allocator: std.mem.Allocator, io: std.Io) ![]const []const u8 {
    if (try env.get(allocator, io, "TARS_SKILLS_DIR")) |raw| {
        defer allocator.free(raw);
        var list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (list.items) |d| allocator.free(d);
            list.deinit(allocator);
        }
        var it = std.mem.splitScalar(u8, raw, ':');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (trimmed.len == 0) continue;
            try list.append(allocator, try allocator.dupe(u8, trimmed));
        }
        if (list.items.len > 0) return list.toOwnedSlice(allocator);
    }
    return defaultDirs(allocator);
}

fn freeDirList(allocator: std.mem.Allocator, dirs: []const []const u8) void {
    for (dirs) |d| allocator.free(d);
    allocator.free(dirs);
}

/// List skill folder names that contain SKILL.md under any search root.
pub fn listSkills(allocator: std.mem.Allocator, io: std.Io) SkillError![]const u8 {
    const dirs = searchDirs(allocator, io) catch return SkillError.OutOfMemory;
    defer freeDirList(allocator, dirs);

    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }

    for (dirs) |root| {
        listInRoot(allocator, io, root, &names) catch continue;
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"skills\":[");
    for (names.items, 0..) |n, i| {
        if (i > 0) try out.appendSlice(allocator, ",");
        const esc = @import("../llm/json_util.zig").escapeString(allocator, n) catch return SkillError.OutOfMemory;
        defer allocator.free(esc);
        try out.appendSlice(allocator, esc);
    }
    try out.appendSlice(allocator, "]}");
    for (names.items) |n| allocator.free(n);
    names.deinit(allocator);
    return out.toOwnedSlice(allocator);
}

fn listInRoot(allocator: std.mem.Allocator, io: std.Io, root: []const u8, names: *std.ArrayList([]const u8)) !void {
    const cmd = try std.fmt.allocPrint(allocator, "find '{s}' -maxdepth 2 -name SKILL.md 2>/dev/null", .{root});
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const skill_md = std.mem.trim(u8, line, " \r");
        const dir = std.fs.path.dirname(skill_md) orelse continue;
        const name = std.fs.path.basename(dir);
        var dup = false;
        for (names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) dup = true;
        }
        if (dup) continue;
        const owned = try allocator.dupe(u8, name);
        try names.append(allocator, owned);
    }
}

/// Load SKILL.md body for a skill name; searches all configured roots.
pub fn loadSkill(allocator: std.mem.Allocator, io: std.Io, name: []const u8) SkillError![]const u8 {
    const dirs = searchDirs(allocator, io) catch return SkillError.OutOfMemory;
    defer freeDirList(allocator, dirs);

    for (dirs) |root| {
        const path = std.fmt.allocPrint(allocator, "{s}/{s}/SKILL.md", .{ root, name }) catch return SkillError.OutOfMemory;
        defer allocator.free(path);

        const cmd = try std.fmt.allocPrint(allocator, "test -f '{s}' && cat '{s}'", .{ path, path });
        defer allocator.free(cmd);

        const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch continue;
        defer allocator.free(result.stderr);

        switch (result.term) {
            .exited => |code| {
                if (code != 0) {
                    allocator.free(result.stdout);
                    continue;
                }
                return result.stdout;
            },
            else => {
                allocator.free(result.stdout);
                continue;
            },
        }
    }
    return SkillError.NotFound;
}
