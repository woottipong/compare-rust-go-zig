const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zap_dep = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
        .openssl = false,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zap", zap_dep.module("zap"));

    const exe = b.addExecutable(.{
        .name = "websocket-public-chat",
        .root_module = exe_mod,
    });
    exe.linkLibrary(zap_dep.artifact("facil.io"));

    b.installArtifact(exe);

    // test step: hub logic (no zap dependency needed)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/hub.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(unit_tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);
}
