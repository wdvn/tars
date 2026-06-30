const std = @import("std");

/// Wire the tars library module, CLI executable, run step, and init-db helper.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tars_mod = b.addModule("tars", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "tars",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tars", .module = tars_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run tars skeleton");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    const init_cmd = b.addSystemCommand(&.{ "bash", "memory/init.sh" });
    const init_step = b.step("init-db", "Initialize .tars/tars.db");
    init_step.dependOn(&init_cmd.step);
}
