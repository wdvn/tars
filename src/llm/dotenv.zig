//! Load `.env` files — mini-agent compatible (shell env wins over file values).

const std = @import("std");

pub const DotEnv = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    /// Search TARS_ENV_FILE, ./.env, ~/.tars/.env and ingest unset keys only.
    pub fn load(allocator: std.mem.Allocator, io: std.Io) !DotEnv {
        var map = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |e| allocator.free(e.key_ptr.*);
            map.deinit();
        }

        if (try shellGet(allocator, io, "TARS_ENV_FILE")) |explicit| {
            defer allocator.free(explicit);
            if (explicit.len > 0) try ingestFile(allocator, io, &map, explicit);
        }

        try ingestFile(allocator, io, &map, ".env");

        if (try shellGet(allocator, io, "HOME")) |home| {
            defer allocator.free(home);
            const path = try std.fmt.allocPrint(allocator, "{s}/.tars/.env", .{std.mem.trim(u8, home, " \r\n")});
            defer allocator.free(path);
            try ingestFile(allocator, io, &map, path);
        }

        return .{ .map = map, .allocator = allocator };
    }

    pub fn deinit(self: *DotEnv) void {
        var it = self.map.iterator();
        while (it.next()) |e| self.allocator.free(e.key_ptr.*);
        self.map.deinit();
    }

    pub fn get(self: *const DotEnv, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }
};

fn shellGet(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !?[]const u8 {
    const script = try std.fmt.allocPrint(allocator, "printenv {s}", .{name});
    defer allocator.free(script);
    const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", script } }) catch return null;
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return null;
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }
    if (result.stdout.len == 0) {
        allocator.free(result.stdout);
        return null;
    }
    return result.stdout;
}

fn ingestFile(allocator: std.mem.Allocator, io: std.Io, map: *std.StringHashMap([]const u8), path: []const u8) !void {
    const cmd = try std.fmt.allocPrint(allocator, "test -f '{s}' && cat '{s}'", .{ path, path });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| if (code != 0) return,
        else => return,
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eff = if (std.mem.startsWith(u8, line, "export "))
            std.mem.trim(u8, line["export ".len..], " \t")
        else
            line;

        const eq = std.mem.indexOfScalar(u8, eff, '=') orelse continue;
        const key = std.mem.trim(u8, eff[0..eq], " \t");
        var val = std.mem.trim(u8, eff[eq + 1 ..], " \t");

        if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
            val = val[1 .. val.len - 1];
        }
        if (key.len == 0 or key.len > 255) continue;

        // Shell environment always wins — skip keys already exported.
        if (try shellGet(allocator, io, key)) |existing| {
            allocator.free(existing);
            continue;
        }

        if (map.contains(key)) continue;
        const owned_key = try allocator.dupe(u8, key);
        errdefer allocator.free(owned_key);
        try map.put(owned_key, val);
    }
}
