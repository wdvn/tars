//! Pattern search in codebase via ripgrep (fallback: grep -r).

const std = @import("std");
const metrics = @import("../metrics/collector.zig");

pub const SearchError = error{
    SearchFailed,
    OutOfMemory,
};

pub fn search(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    pattern: []const u8,
    max_lines: usize,
) SearchError![]const u8 {
    // Prefer ripgrep; fall back to grep when rg is not installed.
    const cmd = try std.fmt.allocPrint(allocator,
        "cd '{s}' && (command -v rg >/dev/null && rg -n --max-count {d} '{s}' . || grep -rn --include='*.*' -m {d} '{s}' . 2>/dev/null) | head -{d}",
        .{ root, max_lines, pattern, max_lines, pattern, max_lines },
    );
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    }) catch return SearchError.SearchFailed;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            // rg/grep exit 1 means "no matches" — still a successful search.
            if (code != 0 and code != 1) {
                allocator.free(result.stdout);
                return SearchError.SearchFailed;
            }
            metrics.gInc("perception.grep.queries", 1);
            metrics.gInc("perception.grep.bytes", @floatFromInt(result.stdout.len));
            return result.stdout;
        },
        else => {
            allocator.free(result.stdout);
            return SearchError.SearchFailed;
        },
    }
}
