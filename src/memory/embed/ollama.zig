//! Ollama /api/embed + `ollama pull` for local embedding models.

const std = @import("std");
const json_util = @import("../../llm/json_util.zig");
const metrics = @import("../../metrics/collector.zig");

pub const OllamaEmbedder = struct {
    host: []const u8,
    model: []const u8,
    output_dim: u32,

    pub fn init(host: []const u8, model: []const u8, output_dim: u32) OllamaEmbedder {
        return .{ .host = host, .model = model, .output_dim = output_dim };
    }

    /// Download model weights via `ollama pull` (respects OLLAMA_HOST).
    pub fn pullModel(allocator: std.mem.Allocator, io: std.Io, host: []const u8, model: []const u8) !void {
        const env_prefix = try std.fmt.allocPrint(allocator, "OLLAMA_HOST='{s}' ", .{host});
        defer allocator.free(env_prefix);
        const cmd = try std.fmt.allocPrint(allocator, "{s}ollama pull '{s}'", .{ env_prefix, model });
        defer allocator.free(cmd);

        const result = try std.process.run(allocator, io, .{
            .argv = &.{ "bash", "-c", cmd },
        });
        defer allocator.free(result.stderr);

        switch (result.term) {
            .exited => |code| {
                allocator.free(result.stdout);
                if (code != 0) return error.PullFailed;
            },
            else => {
                allocator.free(result.stdout);
                return error.PullFailed;
            },
        }
        metrics.gInc("embed.model.pulled", 1);
    }

    /// Probe whether the model tag exists locally (`ollama show`).
    pub fn modelPresent(allocator: std.mem.Allocator, io: std.Io, host: []const u8, model: []const u8) bool {
        const env_prefix = std.fmt.allocPrint(allocator, "OLLAMA_HOST='{s}' ", .{host}) catch return false;
        defer allocator.free(env_prefix);
        const cmd = std.fmt.allocPrint(allocator, "{s}ollama show '{s}' >/dev/null 2>&1", .{ env_prefix, model }) catch return false;
        defer allocator.free(cmd);

        const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return false;
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| return code == 0,
            else => return false,
        }
    }

    pub fn embed(
        self: OllamaEmbedder,
        allocator: std.mem.Allocator,
        io: std.Io,
        input: []const u8,
    ) ![]f32 {
        metrics.gInc("embed.requests.total", 1);

        const escaped = try json_util.escapeString(allocator, input);
        defer allocator.free(escaped);
        const model_esc = try json_util.escapeString(allocator, self.model);
        defer allocator.free(model_esc);

        const body = try std.fmt.allocPrint(allocator, "{{\"model\":{s},\"input\":{s}}}", .{ model_esc, escaped });
        defer allocator.free(body);

        const url = try std.fmt.allocPrint(allocator, "{s}/api/embed", .{self.host});
        defer allocator.free(url);

        const cmd = try std.fmt.allocPrint(allocator,
            \\curl -sS -X POST '{s}' -H 'Content-Type: application/json' -d '{s}'
        , .{ url, body });
        defer allocator.free(cmd);

        const result = std.process.run(allocator, io, .{
            .argv = &.{ "bash", "-c", cmd },
        }) catch {
            metrics.gInc("embed.requests.errors", 1);
            return error.EmbedFailed;
        };
        defer allocator.free(result.stderr);

        switch (result.term) {
            .exited => |code| if (code != 0) {
                metrics.gInc("embed.requests.errors", 1);
                allocator.free(result.stdout);
                return error.EmbedFailed;
            },
            else => {
                metrics.gInc("embed.requests.errors", 1);
                allocator.free(result.stdout);
                return error.EmbedFailed;
            },
        }

        const vec = parseOllamaEmbeddings(allocator, result.stdout, self.output_dim) catch |err| {
            metrics.gInc("embed.requests.errors", 1);
            allocator.free(result.stdout);
            return err;
        };
        allocator.free(result.stdout);
        return vec;
    }
};

pub const EmbedError = error{
    PullFailed,
    EmbedFailed,
    InvalidResponse,
    OutOfMemory,
};

fn parseOllamaEmbeddings(allocator: std.mem.Allocator, body: []const u8, output_dim: u32) ![]f32 {
    var parsed = json_util.parseDynamic(allocator, body) catch return error.InvalidResponse;
    defer parsed.deinit();

    const embeddings_val = json_util.objectGet(parsed.value.object, "embeddings") orelse return error.InvalidResponse;
    if (embeddings_val != .array or embeddings_val.array.items.len == 0) return error.InvalidResponse;

    const first = embeddings_val.array.items[0];
    if (first != .array) return error.InvalidResponse;

    const full_len = first.array.items.len;
    if (full_len == 0) return error.InvalidResponse;

    const take = @min(@as(usize, output_dim), full_len);
    var vec = try allocator.alloc(f32, take);
    errdefer allocator.free(vec);

    for (0..take) |i| {
        const item = first.array.items[i];
        vec[i] = switch (item) {
            .float => @floatCast(item.float),
            .integer => @floatFromInt(item.integer),
            else => {
                allocator.free(vec);
                return error.InvalidResponse;
            },
        };
    }

    normalize(vec);
    return vec;
}

fn normalize(vec: []f32) void {
    var sum: f32 = 0;
    for (vec) |v| sum += v * v;
    if (sum == 0) return;
    const inv = 1.0 / @sqrt(sum);
    for (vec) |*v| v.* *= inv;
}
