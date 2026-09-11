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

    // Also install executable into bin/tars as documented in README
    const bin_install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../bin" } },
    });
    b.getInstallStep().dependOn(&bin_install.step);

    const run_step = b.step("run", "Run tars skeleton");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);

    // Unit tests for library module and executable
    const mod_tests = b.addTest(.{
        .root_module = tars_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const init_cmd = b.addSystemCommand(&.{ "bash", "memory/init.sh" });
    const init_step = b.step("init-db", "Initialize .tars/tars.db");
    init_step.dependOn(&init_cmd.step);
}
